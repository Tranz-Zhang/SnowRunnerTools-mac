// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnowRunnerTool",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "snowrunner-tool", targets: ["snowrunner-tool"]),
        .executable(name: "SnowRunnerModEditor", targets: ["SnowRunnerModEditor"]),
        .library(name: "SnowRunnerModEditorCore", targets: ["SnowRunnerModEditorCore"]),
        .library(name: "SnowRunnerTool", targets: ["SnowRunnerTool"])
    ],
    targets: [
        .target(
            name: "SnowRunnerTool",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .executableTarget(
            name: "snowrunner-tool",
            dependencies: ["SnowRunnerTool"]
        ),
        .executableTarget(
            name: "SnowRunnerModEditor",
            dependencies: ["SnowRunnerModEditorCore"]
        ),
        .target(
            name: "SnowRunnerModEditorCore",
            dependencies: ["SnowRunnerTool"]
        ),
        .testTarget(
            name: "SnowRunnerToolTests",
            dependencies: ["SnowRunnerTool"]
        ),
        .testTarget(
            name: "SnowRunnerModEditorTests",
            dependencies: ["SnowRunnerModEditorCore", "SnowRunnerTool"]
        )
    ]
)
