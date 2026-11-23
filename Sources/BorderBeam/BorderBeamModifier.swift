//
//  BorderBeamModifier.swift
//  BorderBeam iOS 16 port
//
//  SwiftUI facing API. Rendering is delegated to BeamMetalView, so no
//  iOS-17-only SwiftUI shader APIs are used.
//
import SwiftUI
import UIKit

// MARK: - Speed (environment)

private struct BeamSpeedKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

public extension EnvironmentValues {
    /// Speed multiplier for every beam below this view (1 = normal, 2 = twice as fast).
    var beamSpeed: Double {
        get { self[BeamSpeedKey.self] }
        set { self[BeamSpeedKey.self] = newValue }
    }
}

public extension View {
    /// Sets the speed of every `BorderBeam` / `.borderBeam` inside this view.
    ///
    ///     VStack { ... }.beamSpeed(1.5)
    ///
    /// Changing it while a beam runs speeds it up or slows it down smoothly, without jumping.
    func beamSpeed(_ speed: Double) -> some View {
        environment(\.beamSpeed, speed)
    }
}

// MARK: - SwiftUI bridge

private struct BeamLayer: UIViewRepresentable {
    let shape: BeamShape
    let style: BeamStyle
    let direction: BeamDirection
    let active: Bool
    let colors: [Color]
    let intensity: Double
    let timing: BeamTiming

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.beamSpeed) private var speed

    func makeUIView(context: Context) -> BeamMetalView {
        let view = BeamMetalView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: BeamMetalView, context: Context) {
        var config = BeamRenderConfig()
        config.shape = shape
        config.style = style
        config.direction = direction
        config.active = active
        config.colors = colors.isEmpty ? [UIColor.white] : colors.map { UIColor($0) }
        config.intensity = intensity
        config.timing = timing
        config.speed = speed
        config.reduceMotion = reduceMotion
        view.config = config
    }
}

public extension View {
    /// Adds an animated border beam to any view.
    ///
    ///     MyView().borderBeam(shape: .capsule, style: .line)
    ///     MyView().borderBeam(shape: .rounded(12), colors: BeamPalette.single(.cyan))
    func borderBeam(
        shape: BeamShape = .rounded(26),
        style: BeamStyle = .large,
        direction: BeamDirection = .leftToRight,
        active: Bool = true,
        colors: [Color] = BeamPalette.colorful,
        intensity: Double = 1,
        timing: BeamTiming = .default
    ) -> some View {
        overlay {
            BeamLayer(shape: shape, style: style, direction: direction,
                      active: active, colors: colors, intensity: intensity, timing: timing)
        }
        .allowsHitTesting(false)
    }
}
