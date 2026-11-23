Pod::Spec.new do |s|
  s.name         = "BorderBeam"
  s.version      = "1.0.0"
  s.summary      = "GPU-rendered (Metal shader) animated border beam for any SwiftUI view."
  s.homepage     = "https://github.com/ismnoiet/border-beam-ios"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.author       = { "ismnoiet" => "ismnoiet" }

  # iOS 16 port: Metal compute via MTKView instead of SwiftUI colorEffect
  s.platform     = :ios, "16.0"
  s.swift_version = "5.9"

  s.source       = {
    :git => "https://github.com/ismnoiet/border-beam-ios.git",
    :tag => "#{s.version}"
  }

  s.source_files = "Sources/BorderBeam/**/*.swift"
  s.resources    = "Sources/BorderBeam/Shaders/BorderBeam.metal"
  s.frameworks   = "SwiftUI", "Metal", "MetalKit"
end
