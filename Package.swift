// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Join",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JoinCore", targets: ["JoinCore"]),
        .executable(name: "Join", targets: ["Join"]),
    ],
    targets: [
        .target(name: "JoinCore"),
        .executableTarget(name: "Join", dependencies: ["JoinCore"]),
        .testTarget(name: "JoinCoreTests", dependencies: ["JoinCore"]),
    ]
)
