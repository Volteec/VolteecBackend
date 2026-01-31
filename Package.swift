// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VolteecBackend",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", exact: "4.121.1"),
        .package(url: "https://github.com/vapor/fluent.git", exact: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", exact: "2.12.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.94.0"),
        .package(url: "https://github.com/vapor/apns.git", exact: "4.2.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1"),
        // Pin VolteecShared to semver tag for release stability
        .package(url: "https://github.com/Volteec/VolteecShared.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "VolteecBackend",
            dependencies: [
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "VaporAPNS", package: "apns"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "VolteecShared", package: "VolteecShared"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VolteecBackendTests",
            dependencies: [
                .target(name: "VolteecBackend"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
] }
