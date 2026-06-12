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

    func testWorkspaceInitialLoadListBuilderPreservesNonInitialRecordsAndAddsMeshAsInitial() throws {
        let root = try temporaryDirectory(named: "workspace-load-list")
        let initial = root.appendingPathComponent("initial", isDirectory: true)
        try FileManager.default.createDirectory(at: initial, withIntermediateDirectories: true)
        try writeFile(root: initial, relativePath: "[media]/classes/trucks/new.xml", data: Data("<Truck/>".utf8))
        try writeFile(root: initial, relativePath: "[media]/_templates/trucks.xml", data: Data("<Templates/>".utf8))
        try writeFile(root: initial, relativePath: "[meshes]/new_mesh", data: Data([1, 2, 3]))
        try writeFile(root: initial, relativePath: "[strings]/strings_english.str", data: Data("KEY\t\t\"Value\"".utf8))
        try writeFile(root: initial, relativePath: "initial.cache_block", data: Data("cache".utf8))

        let baseManifest = try LoadListBuilder.buildManifest(records: [
            LoadListRecord(
                manifestPath: "<meshes>\\shared_mesh",
                loaderType: "mesh_loader",
                sourcePak: "shared.pak",
                phase: "MESH load"
            ),
            LoadListRecord(
                manifestPath: "<sound>\\sound.sound_list",
                loaderType: "sound_loader",
                sourcePak: "shared_sound.pak",
                phase: "SOUND load"
            ),
            LoadListRecord(
                manifestPath: "<media>\\classes\\trucks\\old.xml",
                loaderType: "cls_loader",
                sourcePak: "initial.pak",
                phase: "CLASSES load"
            )
        ])

        let records = try WorkspaceInitialLoadListBuilder.records(fromInitialDirectory: initial, preservingFrom: baseManifest)

        XCTAssertTrue(records.contains {
            $0.manifestPath == "<meshes>\\shared_mesh" && $0.sourcePak == "shared.pak"
        })
        XCTAssertTrue(records.contains {
            $0.manifestPath == "<sound>\\sound.sound_list" && $0.sourcePak == "shared_sound.pak"
        })
        XCTAssertFalse(records.contains { $0.manifestPath == "<media>\\classes\\trucks\\old.xml" })
        XCTAssertTrue(records.contains {
            $0.manifestPath == "<media>\\classes\\trucks\\new.xml"
                && $0.loaderType == "cls_loader"
                && $0.sourcePak == "initial.pak"
        })
        XCTAssertTrue(records.contains {
            $0.manifestPath == "<media>\\_templates\\trucks.xml"
                && $0.loaderType == "tpl_loader"
                && $0.sourcePak == "initial.pak"
        })
        XCTAssertTrue(records.contains {
            $0.manifestPath == "<meshes>\\new_mesh"
                && $0.loaderType == "mesh_loader"
                && $0.sourcePak == "initial.pak"
        })
        XCTAssertFalse(records.contains { $0.manifestPath.hasPrefix("<strings>\\") })
    }

    func testWorkspaceInitialLoadListBuilderRejectsUnknownLoadListedPath() throws {
        let root = try temporaryDirectory(named: "workspace-load-list-invalid")
        let initial = root.appendingPathComponent("initial", isDirectory: true)
        try FileManager.default.createDirectory(at: initial, withIntermediateDirectories: true)
        try writeFile(root: initial, relativePath: "[media]/unknown/demo.bin", data: Data([1]))

        let baseManifest = try LoadListBuilder.buildManifest(records: [])

        XCTAssertThrowsError(try WorkspaceInitialLoadListBuilder.records(fromInitialDirectory: initial, preservingFrom: baseManifest))
    }
}
