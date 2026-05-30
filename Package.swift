// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnowRunnerTool",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "snowrunner-tool", targets: ["snowrunner-tool"]),
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
        .testTarget(
            name: "SnowRunnerToolTests",
            dependencies: ["SnowRunnerTool"]
        )
    ]
)
