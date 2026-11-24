//
//  TweakMain.swift
//  BorderBeamTweak
//
//  Entry point. `beamShaderSource` is generated at build time from
//  Sources/BorderBeam/Shaders/BorderBeam.metal so the dylib carries the
//  kernel inside itself (an injected dylib has no bundle to read it from).
//
import UIKit

@_cdecl("borderBeam_init")
public func borderBeam_init() {
    BeamMetalView.embeddedShaderSource = beamShaderSource
    BeamHook.install()
}
