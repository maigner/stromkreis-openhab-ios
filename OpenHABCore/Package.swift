// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenHABCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(
            name: "OpenHABCore",
            targets: ["OpenHABCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swhitty/swift-timeout.git", from: "0.4.0")
    ],
    targets: [
        .target(
            name: "OpenHABCore",
            dependencies: [
                .product(name: "Timeout", package: "swift-timeout")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("StrictConcurrency"),
                .unsafeFlags([
                    "-Xfrontend", "-enable-actor-data-race-checks",
                    "-Xfrontend", "-strict-concurrency=complete"
                ])
            ]
        ),
        .testTarget(
            name: "OpenHABCoreTests",
            dependencies: [
                "OpenHABCore"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
