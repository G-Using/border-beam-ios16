// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BorderBeam",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "BorderBeam", targets: ["BorderBeam"]),
        .library(name: "BorderBeamDemo", targets: ["BorderBeamDemo"]),
    ],
    targets: [
        .target(
            name: "BorderBeam",
            path: "Sources/BorderBeam",
            resources: [.copy("Shaders")]   // keep the .metal source; compiled at runtime (works under Theos too)
        ),
        .target(
            name: "BorderBeamDemo",
            dependencies: ["BorderBeam"],
            path: "Sources/BorderBeamDemo"
        ),
    ]
)
