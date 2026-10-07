// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TopOff",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TopOffEngine", targets: ["TopOffEngine"]),
        .library(name: "TopOffPresentation", targets: ["TopOffPresentation"])
    ],
    targets: [
        .target(name: "TopOffEngine"),
        .target(name: "TopOffPresentation", dependencies: ["TopOffEngine"]),
        .testTarget(name: "TopOffEngineTests", dependencies: ["TopOffEngine"])
    ]
)
