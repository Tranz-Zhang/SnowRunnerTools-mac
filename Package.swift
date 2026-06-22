// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnowRunnerTools",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "snowrunner-tool", targets: ["SnowRunnerToolCLI"]),
        .executable(name: "SnowRunnerModEditor", targets: ["SnowRunnerModEditor"]),
        .library(name: "SnowRunnerCore", targets: ["SnowRunnerCore"])
    ],
    targets: [
        .target(
            name: "SnowRunnerCore",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .executableTarget(
            name: "SnowRunnerToolCLI",
            dependencies: ["SnowRunnerCore"]
        ),
        .executableTarget(
            name: "SnowRunnerModEditor",
            dependencies: ["SnowRunnerCore"]
        ),
        .testTarget(
            name: "SnowRunnerCoreTests",
            dependencies: ["SnowRunnerCore"]
        ),
        .testTarget(
            name: "SnowRunnerModEditorTests",
            dependencies: ["SnowRunnerModEditor", "SnowRunnerCore"]
        )
    ]
)
