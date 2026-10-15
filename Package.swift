// swift-tools-version:6.2
import PackageDescription

/// Approachable Concurrency: a nonisolated async function runs on its caller's actor unless it's marked
/// `@concurrent`, and a main-actor type's conformances are isolated to the main actor.
let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Join",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JoinCore", targets: ["JoinCore"]),
        .executable(name: "Join", targets: ["Join"]),
    ],
    targets: [
        // The app's rules, free of UI: nonisolated, so callers decide where they run.
        .target(name: "JoinCore", swiftSettings: approachableConcurrency),
        // The app: on the main actor unless a declaration says otherwise.
        .executableTarget(
            name: "Join",
            dependencies: ["JoinCore"],
            swiftSettings: approachableConcurrency + [.defaultIsolation(MainActor.self)]
        ),
        // Swift Testing; nonisolated like the library it tests.
        .testTarget(name: "JoinCoreTests", dependencies: ["JoinCore"], swiftSettings: approachableConcurrency),
    ],
    swiftLanguageModes: [.v6]
)
