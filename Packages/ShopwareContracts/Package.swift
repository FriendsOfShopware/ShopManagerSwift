// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShopwareContracts",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../ShopwareAdminAPI"), .package(path: "../ShopwareDomain")],
    targets: [
        .testTarget(name: "ShopwareContractsTests", dependencies: [
            .product(name: "ShopwareAdminAPI", package: "ShopwareAdminAPI"),
            .product(name: "ShopwareDomain", package: "ShopwareDomain"),
        ]),
    ]
)
