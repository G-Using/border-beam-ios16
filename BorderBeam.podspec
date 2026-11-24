Pod::Spec.new do |s|
  s.name         = "BorderBeam"
  s.version      = "1.1.0"
  s.summary      = "Animated border beam for any view, ported to iOS 15/16."
  s.homepage     = "https://github.com/G-Using/border-beam-ios16"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author       = { "G-Using" => "G-Using@users.noreply.github.com" }

  # Port of ismnoiet/border-beam-ios: UIKit + Metal compute (MTKView) instead of
  # the iOS 17-only SwiftUI colorEffect pipeline.
  s.platform     = :ios, "15.0"
  s.swift_version = "5.0"

  s.source       = {
    :git => "https://github.com/G-Using/border-beam-ios16.git",
    :tag => "#{s.version}"
  }

  s.source_files = "Sources/BorderBeam/**/*.swift"
  s.resources    = "Sources/BorderBeam/Shaders/BorderBeam.metal"
  s.frameworks   = "SwiftUI", "Metal", "MetalKit"
end
