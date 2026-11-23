//
//  DemoApp.swift
//  BorderBeam iOS 15/16 demo app
//
//  Standalone application target, packaged into a .deb for rootless / roothide
//  jailbroken devices. Kept out of Package.swift so SPM builds stay library-only.
//
import SwiftUI

@main
struct BorderBeamDemoApp: App {
    var body: some Scene {
        WindowGroup {
            BorderBeamExamples()
        }
    }
}
