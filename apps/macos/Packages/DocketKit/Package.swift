// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DocketKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DocketCore", targets: ["DocketCore"]),
        .library(name: "DocketActivity", targets: ["DocketActivity"]),
        .library(name: "DocketGitHub", targets: ["DocketGitHub"]),
        .library(name: "DocketPersistence", targets: ["DocketPersistence"]),
        .library(name: "DocketNotify", targets: ["DocketNotify"]),
        .library(name: "DocketUpdate", targets: ["DocketUpdate"]),
        .library(name: "DocketStores", targets: ["DocketStores"]),
        .executable(name: "docket-cli", targets: ["DocketCLI"]),
    ],
    targets: [
        .target(name: "DocketCore"),
        .target(name: "DocketActivity", dependencies: ["DocketCore"]),
        .target(name: "DocketGitHub", dependencies: ["DocketCore"]),
        .target(name: "DocketPersistence", dependencies: ["DocketCore"]),
        .target(name: "DocketNotify", dependencies: ["DocketCore"]),
        .target(name: "DocketUpdate", dependencies: ["DocketCore"]),
        .target(
            name: "DocketStores", dependencies: ["DocketCore", "DocketActivity", "DocketPersistence", "DocketUpdate"]),
        .target(name: "DocketTestSupport", dependencies: ["DocketCore"]),
        .executableTarget(name: "DocketCLI", dependencies: ["DocketCore", "DocketActivity", "DocketGitHub"]),
        .testTarget(name: "DocketCoreTests", dependencies: ["DocketCore"]),
        .testTarget(name: "DocketActivityTests", dependencies: ["DocketActivity", "DocketTestSupport"]),
        .testTarget(name: "DocketGitHubTests", dependencies: ["DocketGitHub"]),
        .testTarget(name: "DocketPersistenceTests", dependencies: ["DocketPersistence"]),
        .testTarget(name: "DocketNotifyTests", dependencies: ["DocketNotify"]),
        .testTarget(name: "DocketUpdateTests", dependencies: ["DocketUpdate"]),
        .testTarget(name: "DocketStoresTests", dependencies: ["DocketStores", "DocketTestSupport"]),
    ]
)
