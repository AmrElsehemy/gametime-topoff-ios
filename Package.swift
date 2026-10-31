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
        .library(name: "TopOffPresentation", targets: ["TopOffPresentation"]),
        .library(name: "TopOffMonetization", targets: ["TopOffMonetization"]),
        .library(name: "TopOffAnalytics", targets: ["TopOffAnalytics"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/AmrElsehemy/gametime-ios.git",
            revision: "5906bd8966ea87b4fce8876c2701c4b9ed74664c"
        )
    ],
    targets: [
        .target(name: "TopOffEngine"),
        .target(
            name: "TopOffPresentation",
            dependencies: [
                "TopOffEngine",
                .product(name: "GameTimeExperience", package: "gametime-ios")
            ]
        ),
        .target(
            name: "TopOffMonetization",
            dependencies: [
                .product(name: "GameTimeCommerce", package: "gametime-ios"),
                .product(name: "GameTimeAdMob", package: "gametime-ios")
            ]
        ),
        .target(
            name: "TopOffAnalytics",
            dependencies: [
                .product(name: "GameTimeServices", package: "gametime-ios"),
                .product(name: "GameTimeAnalytics", package: "gametime-ios")
            ]
        ),
        .testTarget(name: "TopOffEngineTests", dependencies: ["TopOffEngine"]),
        .testTarget(
            name: "TopOffAnalyticsTests",
            dependencies: [
                "TopOffAnalytics",
                .product(name: "GameTimeServices", package: "gametime-ios")
            ]
        ),
        .testTarget(
            name: "TopOffMonetizationTests",
            dependencies: [
                "TopOffMonetization",
                .product(name: "GameTimeCommerce", package: "gametime-ios")
            ]
        )
    ]
)
