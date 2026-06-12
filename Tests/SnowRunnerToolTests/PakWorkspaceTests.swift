import Foundation
import XCTest
@testable import SnowRunnerTool

final class PakWorkspaceTests: XCTestCase {
    func testWorkspaceManifestRoundTrips() throws {
        let manifest = PakWorkspaceManifest(
            version: 1,
            initialSourcePath: "/game/initial.pak",
            mods: [
                PakWorkspaceMod(
                    sourcePath: "/mods/demo.pak",
                    folderName: "demo",
                    archiveName: "demo.pak",
                    sourceCachePath: ".snowrunner/sources/demo.pak",
                    entries: [
                        PakWorkspaceSourceEntry(
                            sourceEntryName: "prebuild/textures/pct/foo.pct",
                            workspacePath: "mods/demo/prebuild/textures/pct/foo.pct",
                            sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                        )
                    ]
                )
            ],
            policy: PakWorkspacePolicy(textureMode: "inlineInitial", allowInitialOverwrite: true)
        )

        let data = try JSONEncoder.pakWorkspace.encode(manifest)
        let decoded = try JSONDecoder.pakWorkspace.decode(PakWorkspaceManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }

    func testWorkspacePathsAreStable() {
        let root = URL(fileURLWithPath: "/tmp/workspace", isDirectory: true)

        XCTAssertEqual(PakWorkspacePaths.manifestURL(root: root).path, "/tmp/workspace/.snowrunner-workspace.json")
        XCTAssertEqual(PakWorkspacePaths.initialDirectory(root: root).path, "/tmp/workspace/initial")
        XCTAssertEqual(PakWorkspacePaths.modsDirectory(root: root).path, "/tmp/workspace/mods")
        XCTAssertEqual(PakWorkspacePaths.buildInitialPak(root: root).path, "/tmp/workspace/build/initial.pak")
        XCTAssertEqual(PakWorkspacePaths.buildReport(root: root).path, "/tmp/workspace/build/workspace-build-report.md")
        XCTAssertEqual(PakWorkspacePaths.sourceCache(root: root, folderName: "demo").path, "/tmp/workspace/.snowrunner/sources/demo.pak")
    }
}
