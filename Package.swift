// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OMPAPIManager",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OMPAPIManagerCore", targets: ["OMPAPIManagerCore"]),
        .executable(name: "OMPAPIManager", targets: ["OMPAPIManagerApp"])
    ],
    dependencies: [
        // Pin the exact parser version so production configuration handling is reproducible.
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.1.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.99.0")
    ],
    targets: [
        .target(
            name: "OMPAPIManagerCore",
            dependencies: [
                "Yams",
                "CSQLite",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio")
            ],
            path: "Sources/OMPAPIManagerCore"
        ),
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .executableTarget(
            name: "OMPAPIManagerApp",
            dependencies: ["OMPAPIManagerCore"],
            path: "Sources/OMPAPIManagerApp"
        ),
        .testTarget(
            name: "OMPAPIManagerCoreTests",
            dependencies: ["OMPAPIManagerCore"],
            path: "Tests/OMPAPIManagerCoreTests"
        )
    ]
)
