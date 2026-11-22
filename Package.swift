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
        .library(name: "TopOffAnalytics", targets: ["TopOffAnalytics"]),
        .library(name: "TopOffSave", targets: ["TopOffSave"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/AmrElsehemy/gametime-ios.git",
            revision: "e7572855b4e78087888ca0a3acd9207253d8df5a"
        )
    ],
    targets: [
        .target(
            name: "TopOffEngine",
            dependencies: [
                .product(name: "GameTimeCore", package: "gametime-ios")
            ]
        ),
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
        .target(
            name: "TopOffSave",
            dependencies: [
                "TopOffEngine",
                .product(name: "GameTimePersistence", package: "gametime-ios")
            ]
        ),
        .testTarget(name: "TopOffEngineTests", dependencies: ["TopOffEngine"]),
        .testTarget(
            name: "TopOffSaveTests",
            dependencies: [
                "TopOffSave",
                .product(name: "GameTimePersistence", package: "gametime-ios")
            ]
        ),
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
