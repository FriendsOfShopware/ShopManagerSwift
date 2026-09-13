// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShopwareDomain",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ShopwareDomain", targets: ["ShopwareDomain"])],
    dependencies: [.package(path: "../ShopwareAdminAPI")],
    targets: [
        .target(name: "ShopwareDomain", dependencies: ["ShopwareAdminAPI"],
                resources: [.process("Resources")]),
        .testTarget(name: "ShopwareDomainTests", dependencies: ["ShopwareDomain"]),
    ]
)
