//
//  BeamSweepView.swift
//  BorderBeamTweak
//
//  CoreAnimation-only beam ring.
//
//  Why not Metal here: an injected dylib has no bundle to read a metallib from,
//  and a compute pipeline that fails (or a kernel whose SDF is slightly off)
//  renders nothing at all — which on a device is indistinguishable from "the
//  tweak never loaded". CAGradientLayer + a stroke mask always draws.
//
//  Layers per pass:
//    host (plain CALayer, clipped by a stroke-only mask)
//      └── conic CAGradientLayer, rotating
//  The mask is static, the gradient spins, so the lit arc travels around the
//  border without the rounded rect itself rotating.
//

import UIKit
import QuartzCore

final class BeamSweepView: UIView {

    private struct Pass {
        let host: CALayer
        let mask: CAShapeLayer
        let gradient: CAGradientLayer
        let lineWidth: CGFloat
        let inset: CGFloat
    }

    private var passes: [Pass] = []
    private let palette: [UIColor]
    private let cornerRadius: CGFloat
    private let spinDuration: CFTimeInterval
    private let spinKey = "borderbeam.spin"

    init(frame: CGRect, cornerRadius: CGFloat, palette: [UIColor], spinDuration: CFTimeInterval = 3.4) {
        self.palette = palette
        self.cornerRadius = cornerRadius
        self.spinDuration = spinDuration
        super.init(frame: frame)

        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
        alpha = 0

        // Widths follow the field's height so a 36pt pill and a 120pt text view
        // both look right.
        let h = max(frame.height, 24)
        let glowWidth = min(max(h * 0.30, 6), 15)
        let coreWidth = min(max(h * 0.075, 1.8), 3)

        // Soft halo, fully inside the bounds so the host's clipsToBounds cannot
        // eat it.
        passes.append(makePass(lineWidth: glowWidth, inset: glowWidth * 0.5, opacity: 0.45))
        // Bright edge line.
        passes.append(makePass(lineWidth: coreWidth, inset: min(coreWidth * 0.7, 2.5), opacity: 1.0))
    }

    required init?(coder: NSCoder) {
        fatalError("BeamSweepView is code-only")
    }

    // MARK: - Passes

    private func makePass(lineWidth: CGFloat, inset: CGFloat, opacity: Float) -> Pass {
        let host = CALayer()
        let mask = CAShapeLayer()
        mask.fillColor = UIColor.clear.cgColor
        mask.strokeColor = UIColor.white.cgColor
        mask.lineWidth = lineWidth
        mask.lineCap = .round
        mask.lineJoin = .round
        host.mask = mask
        layer.addSublayer(host)

        let gradient = CAGradientLayer()
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        gradient.opacity = opacity
        host.addSublayer(gradient)

        applyColors(to: gradient)
        return Pass(host: host, mask: mask, gradient: gradient, lineWidth: lineWidth, inset: inset)
    }

    /// Comet: fades in, runs through the whole palette, fades out, then a long
    /// transparent tail so only one bright arc is visible at a time.
    private func applyColors(to gradient: CAGradientLayer) {
        let ramp = palette.isEmpty ? [UIColor.white] : palette
        let n = CGFloat(ramp.count)

        var colors: [CGColor] = [UIColor.clear.cgColor]
        var locations: [NSNumber] = [0]

        let start: CGFloat = 0.08
        let end: CGFloat = 0.46
        for (i, color) in ramp.enumerated() {
            let t = start + (end - start) * CGFloat(i) / max(n - 1, 1)
            colors.append(color.cgColor)
            locations.append(NSNumber(value: Double(t)))
        }
        colors.append(UIColor.clear.cgColor)
        locations.append(NSNumber(value: Double(min(end + 0.10, 0.95))))
        colors.append(UIColor.clear.cgColor)
        locations.append(1.0)

        gradient.colors = colors
        gradient.locations = locations
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 8, bounds.height > 8 else { return }

        // Square big enough to still cover the ring at any rotation angle.
        let side = hypot(bounds.width, bounds.height) * 1.15
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for pass in passes {
            pass.host.frame = bounds
            pass.mask.frame = bounds
            pass.gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            pass.gradient.position = center

            let rect = bounds.insetBy(dx: pass.inset, dy: pass.inset)
            guard rect.width > 2, rect.height > 2 else { continue }
            let radius = max(min(cornerRadius - pass.inset, min(rect.width, rect.height) * 0.5), 0)
            pass.mask.path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
        }
        CATransaction.commit()
    }

    // MARK: - Animation

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncSpin()
        if window != nil, alpha < 1 {
            UIView.animate(withDuration: 0.25, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.alpha = 1
            }
        }
    }

    private func syncSpin() {
        let shouldRun = window != nil && !UIAccessibility.isReduceMotionEnabled
        for pass in passes {
            if shouldRun {
                if pass.gradient.animation(forKey: spinKey) == nil {
                    let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                    spin.fromValue = 0.0
                    spin.toValue = Double.pi * 2
                    spin.duration = spinDuration
                    spin.repeatCount = .infinity
                    spin.timingFunction = CAMediaTimingFunction(name: .linear)
                    spin.isRemovedOnCompletion = false
                    pass.gradient.add(spin, forKey: spinKey)
                }
            } else {
                pass.gradient.removeAnimation(forKey: spinKey)
            }
        }
    }

    func setSpinning(_ spinning: Bool) {
        if spinning { syncSpin() } else {
            for pass in passes { pass.gradient.removeAnimation(forKey: spinKey) }
        }
    }
}
