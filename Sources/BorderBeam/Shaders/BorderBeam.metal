//
//  BorderBeam.metal
//  Based on the original work by ismnoiet (MIT).
//  iOS 16 port: SwiftUI_Metal.h / [[stitchable]] removed, rewritten as a
//  standalone Metal compute kernel driven by an MTKView. Visual math unchanged.
//
#include <metal_stdlib>
using namespace metal;

#ifndef M_PI_F
#define M_PI_F 3.14159265358979323846f
#endif

struct BeamUniforms {
    float2 size;          // view size in POINTS (shader works in point space)
    float cornerRadius;   // in points, clamped to half the shortest side
    float phase;          // 0...1, loops
    float direction;      // +1 clockwise, -1 counter-clockwise
    float mode;           // 0 orbit, 1 sweep along an edge
    float side;           // mode 1: 1 top, 2 bottom, 3 left, 4 right
    float arc;            // mode 0: comet length as fraction of lap
    float glow;           // soft glow reach in points
    float intensity;      // 0...1
    int   colorCount;     // number of float4 entries in the palette buffer
    float pixelScale;     // texture pixels per point
};

// Signed distance to a rounded box centred at the origin (negative inside).
static float sdRoundedBox(float2 p, float2 hs, float r) {
    float2 q = abs(p) - (hs - r);
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Position along the border, measured clockwise from the right-edge midpoint, as 0...1.
static float perimeterParam(float2 p, float2 hs, float r) {
    float2 ih = max(hs - r, float2(0.0));
    float q = M_PI_F * r * 0.5;
    float L = 4.0 * ih.x + 4.0 * ih.y + 4.0 * q;
    float baseBL = ih.y + q + 2.0 * ih.x;
    float baseL  = baseBL + q;
    float baseTL = baseL + 2.0 * ih.y;
    float baseTR = baseTL + q + 2.0 * ih.x;
    float2 ap = abs(p);
    float s;
    if (ap.x > ih.x && ap.y > ih.y) {
        float2 v = ap - ih;
        float ang = atan2(v.y, v.x);
        if (p.x >= 0.0 && p.y >= 0.0)      { s = ih.y + r * ang; }
        else if (p.x < 0.0 && p.y >= 0.0)  { s = baseBL + r * (M_PI_F * 0.5 - ang); }
        else if (p.x < 0.0)                { s = baseTL + r * ang; }
        else                               { s = baseTR + r * (M_PI_F * 0.5 - ang); }
    } else if ((hs.x - ap.x) < (hs.y - ap.y)) {
        if (p.x >= 0.0) { s = p.y >= 0.0 ? p.y : L + p.y; }
        else            { s = baseL + (ih.y - p.y); }
    } else {
        if (p.y >= 0.0) { s = ih.y + q + (ih.x - p.x); }
        else            { s = baseTL + q + (p.x + ih.x); }
    }
    return fract(s / max(L, 0.001));
}

// Linear blend across the packed RGBA palette.
static float4 samplePalette(constant float4 *c, int n, float t) {
    if (n <= 0) { return float4(1.0); }
    if (n == 1) { return c[0]; }
    float x = clamp(t, 0.0, 1.0) * float(n - 1);
    int i = min(int(floor(x)), n - 2);
    float f = x - float(i);
    return mix(c[i], c[i + 1], f);
}

// Inverse of perimeterParam: point on the border at distance s, clockwise from
// the right-edge midpoint.
static float2 boundaryPoint(float s, float2 hs, float r) {
    float2 ih = max(hs - r, float2(0.0));
    float q = M_PI_F * r * 0.5;
    float L = 4.0 * ih.x + 4.0 * ih.y + 4.0 * q;
    s = s - L * floor(s / max(L, 0.001));
    float l;
    l = ih.y;       if (s < l) { return float2(hs.x, s); }                                   s -= l;
    l = q;          if (s < l) { float a = s / r;                    return float2( ih.x,  ih.y) + r * float2(cos(a), sin(a)); } s -= l;
    l = 2.0 * ih.x; if (s < l) { return float2(ih.x - s, hs.y); }                            s -= l;
    l = q;          if (s < l) { float a = M_PI_F * 0.5 + s / r;     return float2(-ih.x,  ih.y) + r * float2(cos(a), sin(a)); } s -= l;
    l = 2.0 * ih.y; if (s < l) { return float2(-hs.x, ih.y - s); }                           s -= l;
    l = q;          if (s < l) { float a = M_PI_F + s / r;           return float2(-ih.x, -ih.y) + r * float2(cos(a), sin(a)); } s -= l;
    l = 2.0 * ih.x; if (s < l) { return float2(-ih.x + s, -hs.y); }                          s -= l;
    l = q;          if (s < l) { float a = M_PI_F * 1.5 + s / r;     return float2( ih.x, -ih.y) + r * float2(cos(a), sin(a)); } s -= l;
    return float2(hs.x, -ih.y + s);
}

// Wide soft glow = a chain of Gaussian blobs laid along the beam's path.
static float4 orbitGlowBlobs(float2 p, float dist, float2 hs, float r, float phase,
                             float direction, float arc, float sigmaBase,
                             constant float4 *colors, int count) {
    float2 ih = max(hs - r, float2(0.0));
    float q = M_PI_F * r * 0.5;
    float L = 4.0 * ih.x + 4.0 * ih.y + 4.0 * q;

    const int K = 24;
    float delta = arc * L / float(K);
    float sigma = max(sigmaBase, 0.8 * delta);
    if (dist > 3.0 * sigma) { return float4(0.0); }
    float inv2s2 = 0.5 / (sigma * sigma);
    float norm = delta / (sigma * 2.50663);

    float start = 1.0 - arc;
    float4 acc = float4(0.0);
    for (int k = 0; k < K; k++) {
        float t = (float(k) + 0.5) / float(K);
        float sp = fract(start + t * arc + direction * phase);
        float2 pt = boundaryPoint(sp * L, hs, r);
        float2 dv = p - pt;
        float g = exp(-dot(dv, dv) * inv2s2);
        if (g < 0.003) { continue; }
        float bell = pow(sin(M_PI_F * t), 1.6);
        float4 c4 = samplePalette(colors, count, t);
        float v = g * norm * bell * clamp(c4.a, 0.0, 1.0);
        acc += float4(c4.rgb * v, v);
    }
    return acc;
}

static float4 beamColor(float2 position, constant BeamUniforms &u, constant float4 *colors) {
    float2 size = u.size;
    float2 hs = size * 0.5;
    float r = min(u.cornerRadius, min(hs.x, hs.y));
    float2 p = position - hs;
    float dist = -sdRoundedBox(p, hs, r);
    if (dist < 0.0) { return float4(0.0); }

    float4 acc = float4(0.0);

    if (u.mode < 0.5) {
        float a = perimeterParam(p, hs, r);
        float tt = (fract(a - u.direction * u.phase) - (1.0 - u.arc)) / u.arc;
        if (tt >= 0.0) {
            float profile = pow(sin(M_PI_F * clamp(tt, 0.0, 1.0)), 1.2);
            float crisp = 1.0 - smoothstep(0.5, 2.25, dist);
            float halo = 0.6 * exp(-dist / max(u.glow * 0.1, 0.6));
            float4 c4 = samplePalette(colors, u.colorCount, tt);
            float w = (crisp + halo) * profile * clamp(c4.a, 0.0, 1.0);
            acc += float4(c4.rgb * w, w);
        }
        acc += 0.55 * orbitGlowBlobs(p, dist, hs, r, u.phase, u.direction, u.arc,
                                     max(u.glow, 0.001) * 0.7, colors, u.colorCount);
    } else {
        float edgeU;
        float edgeDist;
        int s = int(u.side + 0.5);
        if (s == 1)      { edgeU = position.x / size.x; edgeDist = position.y; }
        else if (s == 2) { edgeU = position.x / size.x; edgeDist = size.y - position.y; }
        else if (s == 3) { edgeU = position.y / size.y; edgeDist = position.x; }
        else             { edgeU = position.y / size.y; edgeDist = size.x - position.x; }

        float len = 0.28;
        float tri = u.phase < 0.5 ? u.phase * 2.0 : (1.0 - u.phase) * 2.0;
        float eased = tri * tri * (3.0 - 2.0 * tri);
        float c = len * 0.5 + (1.0 - len) * eased;
        float k = (edgeU - (c - len * 0.5)) / len;
        if (k < 0.0 || k > 1.0) { return float4(0.0); }
        float tp = 1.0 - abs(2.0 * k - 1.0);
        float profile = tp * tp * (3.0 - 2.0 * tp);
        float4 c4 = samplePalette(colors, u.colorCount, k);

        float crisp = 1.0 - smoothstep(0.5, 2.25, edgeDist);
        float halo = 0.8 * exp(-edgeDist / max(u.glow * 0.2, 0.5));
        float wide = 0.6 * exp(-pow(edgeDist / max(u.glow, 0.001), 1.4));
        float w = ((crisp + halo) * profile + wide * profile) * clamp(c4.a, 0.0, 1.0);
        acc += float4(c4.rgb * w, w);
    }

    float total = acc.a;
    if (total <= 0.0001) { return float4(0.0); }
    float3 rgb = acc.rgb / total;
    float a = clamp(total * u.intensity, 0.0, 1.0);
    return float4(rgb * a, a); // premultiplied
}

kernel void borderBeamKernel(
    texture2d<float, access::write> out [[texture(0)]],
    constant BeamUniforms &u [[buffer(0)]],
    constant float4 *colors [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
    float2 position = (float2(gid) + float2(0.5)) / u.pixelScale;
    out.write(beamColor(position, u, colors), gid);
}
