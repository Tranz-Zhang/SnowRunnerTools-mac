// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnowRunnerTools",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "snowrunner-tool", targets: ["SnowRunnerToolCLI"]),
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
        .testTarget(
            name: "SnowRunnerCoreTests",
            dependencies: ["SnowRunnerCore"],
            exclude: ["Fixtures"]
        )
    ]
)
