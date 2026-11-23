//
//  BeamMetalView.swift
//  BorderBeam iOS 16 port
//
//  The rendering core. Pure UIKit + Metal compute, no SwiftUI shader APIs.
//  Can be used directly from UIKit / a jailbreak tweak, or wrapped by
//  UIViewRepresentable for SwiftUI.
//
import UIKit
import Metal
import MetalKit

// MARK: - Config

public struct BeamRenderConfig: Equatable {
    public var style: BeamStyle = .large
    public var shape: BeamShape = .rounded(26)
    public var direction: BeamDirection = .leftToRight
    public var colors: [UIColor] = []
    public var intensity: CGFloat = 1
    public var timing: BeamTiming = .default
    public var speed: Double = 1
    public var active: Bool = true
    public var reduceMotion: Bool = false

    public init() {}
}

// Must match the Metal struct exactly (48 bytes).
private struct BeamUniforms {
    var size: SIMD2<Float>
    var cornerRadius: Float
    var phase: Float
    var direction: Float
    var mode: Float
    var side: Float
    var arc: Float
    var glow: Float
    var intensity: Float
    var colorCount: Int32
    var pixelScale: Float
}

private final class BeamMetalToken {}

// MARK: - View

public final class BeamMetalView: UIView, MTKViewDelegate {

    private let mtkView: MTKView
    private let device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipeline: MTLComputePipelineState?
    private var uniformBuffer: MTLBuffer?
    private var paletteBuffer: MTLBuffer?

    private var phase: Float = Float.random(in: 0..<1)
    private var lastTime: CFTimeInterval?

    public var config: BeamRenderConfig = BeamRenderConfig() {
        didSet { applyConfig(from: oldValue) }
    }

    // MARK: Init

    public override init(frame: CGRect) {
        let d = MTLCreateSystemDefaultDevice()
        device = d
        mtkView = MTKView(frame: .zero, device: d)
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        let d = MTLCreateSystemDefaultDevice()
        device = d
        mtkView = MTKView(frame: .zero, device: d)
        super.init(coder: coder)
        setup()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setup() {
        isUserInteractionEnabled = false
        backgroundColor = .clear

        mtkView.frame = bounds
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.isOpaque = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.framebufferOnly = false      // required: compute writes into the drawable
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 60
        mtkView.isUserInteractionEnabled = false
        mtkView.delegate = self
        addSubview(mtkView)

        commandQueue = device?.makeCommandQueue()
        uniformBuffer = device?.makeBuffer(
            length: MemoryLayout<BeamUniforms>.size,
            options: .storageModeShared
        )
        loadPipeline()
        rebuildPalette()

        config.reduceMotion = UIAccessibility.isReduceMotionEnabled
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    private func loadPipeline() {
        guard let device = self.device else { return }
        let bundle: Bundle
        #if SWIFT_PACKAGE
        bundle = Bundle.module
        #else
        bundle = Bundle(for: BeamMetalToken.self)
        #endif

        // 1) precompiled metallib, if the host packaged one.
        //    makeDefaultLibrary(bundle:) is throwing and non-optional, so wrap it.
        var library: MTLLibrary? = try? device.makeDefaultLibrary(bundle: bundle)

        // 2) otherwise compile the .metal source at runtime.
        //    This is the path used by plain .app bundles and Theos packages.
        if library == nil, let url = Self.metalSourceURL(in: bundle),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            library = try? device.makeLibrary(source: source, options: nil)
        }

        guard let library, let function = library.makeFunction(name: "borderBeamKernel") else {
            NSLog("BorderBeam: borderBeamKernel not found")
            return
        }
        pipeline = try? device.makeComputePipelineState(function: function)
    }

    /// Looks for BorderBeam.metal at the bundle root, in a Shaders/ subfolder,
    /// or one level down (handles SPM/.copy and hand-built .app layouts).
    private static func metalSourceURL(in bundle: Bundle) -> URL? {
        let name = "BorderBeam.metal"
        if let u = bundle.url(forResource: "BorderBeam", withExtension: "metal") { return u }
        if let u = bundle.url(forResource: "BorderBeam", withExtension: "metal",
                              subdirectory: "Shaders") { return u }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: bundle.bundleURL,
                                                     includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]) else { return nil }
        for item in items {
            if item.lastPathComponent == name { return item }
            guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let sub = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil),
               let hit = sub.first(where: { $0.lastPathComponent == name }) {
                return hit
            }
        }
        return nil
    }

    // MARK: Config application

    private func applyConfig(from old: BeamRenderConfig) {
        if config.colors != old.colors {
            rebuildPalette()
        }
        if config.active != old.active {
            applyActive(animated: true)
        }
        if config.reduceMotion != old.reduceMotion && config.reduceMotion {
            mtkView.isPaused = true
            phase = 0.15
            mtkView.isPaused = false   // one frame with the static beam
        }
        if !config.active && !config.reduceMotion {
            mtkView.isPaused = true
        }
    }

    private func applyActive(animated: Bool) {
        if config.active {
            mtkView.isPaused = false
            lastTime = nil             // no jump after a pause
            if animated {
                UIView.animate(withDuration: config.timing.fade, delay: 0,
                               options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.mtkView.alpha = 1
                }
            } else {
                mtkView.alpha = 1
            }
        } else {
            let fade: () -> Void = { self.mtkView.alpha = 0 }
            let done: (Bool) -> Void = { [weak self] finished in
                guard finished, let self, !self.config.active else { return }
                self.mtkView.isPaused = true
            }
            if animated {
                UIView.animate(withDuration: config.timing.fade, delay: 0,
                               options: [.beginFromCurrentState, .allowUserInteraction],
                               animations: fade, completion: done)
            } else {
                fade()
                done(true)
            }
        }
    }

    @objc private func reduceMotionChanged() {
        let newValue = UIAccessibility.isReduceMotionEnabled
        if newValue != config.reduceMotion { config.reduceMotion = newValue }
    }

    public override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        rebuildPalette()   // resolve dynamic colors for the new appearance
    }

    // MARK: Palette

    private func rebuildPalette() {
        guard let device = self.device else { return }
        let src: [UIColor] = config.colors.isEmpty ? [.white] : Array(config.colors.prefix(16))
        let trait = traitCollection
        var packed = [SIMD4<Float>]()
        packed.reserveCapacity(src.count)

        for color in src {
            let resolved = color.resolvedColor(with: trait)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
            packed.append(SIMD4<Float>(Float(r), Float(g), Float(b), Float(a)))
        }
        paletteBuffer = device.makeBuffer(
            bytes: &packed,
            length: packed.count * MemoryLayout<SIMD4<Float>>.size,
            options: .storageModeShared
        )
    }

    private var glowReach: Float {
        switch config.style {
        case .large: return 20
        case .small: return 4
        case .line:  return 10
        }
    }

    // MARK: Clock

    /// Accumulates phase frame by frame so changing the speed never jumps.
    private func advancePhase() {
        if config.reduceMotion {
            phase = 0.15
            return
        }
        let now = CACurrentMediaTime()
        defer { lastTime = now }
        guard let last = lastTime, config.active else { return }

        let dt = min(max(now - last, 0), 0.1)   // ignore long pauses
        let duration = config.style == .line ? config.timing.lineDuration
                                             : config.timing.rotateDuration
        let rate = max(config.speed, 0) / max(duration, 0.01)
        phase += Float(dt * rate)
        phase -= floorf(phase)
    }

    // MARK: MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandQueue = self.commandQueue,
              let pipeline = self.pipeline,
              let uniformBuffer = self.uniformBuffer,
              let paletteBuffer = self.paletteBuffer else { return }

        advancePhase()

        let pixelW = view.drawableSize.width
        let pixelH = view.drawableSize.height
        let scale = pixelW / max(bounds.width, 1)
        let count = config.colors.isEmpty ? 1 : min(config.colors.count, 16)

        var u = BeamUniforms(
            size: SIMD2<Float>(Float(bounds.width), Float(bounds.height)),
            cornerRadius: Float(config.shape.cornerRadius),
            phase: phase,
            direction: config.direction.shaderValue,
            mode: config.style == .line ? 1 : 0,
            side: 2,                                    // bottom edge for .line
            arc: config.style == .small ? 0.5 : 0.36,
            glow: glowReach,
            intensity: Float(config.intensity),
            colorCount: Int32(count),
            pixelScale: Float(scale)
        )
        uniformBuffer.contents().copyMemory(from: &u, byteCount: MemoryLayout<BeamUniforms>.size)

        guard let command = commandQueue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(drawable.texture, index: 0)
        encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.setBuffer(paletteBuffer, offset: 0, index: 1)

        let tw = pipeline.threadExecutionWidth
        let th = max(pipeline.maxTotalThreadsPerThreadgroup / tw, 1)
        let group = MTLSize(width: tw, height: th, depth: 1)
        let groups = MTLSize(width: (Int(pixelW) + tw - 1) / tw,
                             height: (Int(pixelH) + th - 1) / th,
                             depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: group)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}
