// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShopwareAdminAPI",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ShopwareAdminAPI", targets: ["ShopwareAdminAPI"]),
    ],
    targets: [
        .target(
            name: "ShopwareAdminAPI",
            resources: [.process("Resources")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "ShopwareAdminAPITests",
            dependencies: ["ShopwareAdminAPI"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
