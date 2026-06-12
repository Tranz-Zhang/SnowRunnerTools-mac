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

    func testDirectoryModMappingReusesCachedCompressedPCTWhenUnchanged() throws {
        let root = try temporaryDirectory(named: "workspace-directory-map")
        let modRoot = root.appendingPathComponent("mods/pc", isDirectory: true)
        let pct = makeSyntheticPCT(tableCount: 2)
        try writeFile(root: modRoot, relativePath: "prebuild/textures/pct/demo.pct", data: pct)
        let localExtraField = Data([0x01, 0x00, 0x02, 0x00, 0xAA, 0xBB])
        let centralExtraField = Data([0x02, 0xF0, 0x04, 0x00, 1, 2, 3, 4])
        let sourceTexture = try makeTexturePakWithRawDeflatedEntry(
            internalName: "prebuild/textures/pct/demo.pct",
            data: pct,
            localExtraField: localExtraField,
            centralExtraField: centralExtraField
        )
        let sourcePak = sourceTexture.url
        let sha = ModArchiveMapper.sha256Hex(uncompressedPayload: pct)
        let entries = [
            PakWorkspaceSourceEntry(
                sourceEntryName: "prebuild/textures/pct/demo.pct",
                workspacePath: "mods/pc/prebuild/textures/pct/demo.pct",
                sha256: sha
            )
        ]

        let mapped = try ModArchiveMapper.mapDirectory(
            at: modRoot,
            archiveName: "pc.pak",
            sourceCache: sourcePak,
            sourceEntries: entries,
            workspaceRoot: root
        )

        let pctEntry = try XCTUnwrap(mapped.first { $0.internalName == "[textures]\\pct\\demo.pct" })
        XCTAssertNotNil(pctEntry.compressedPayload)
        XCTAssertEqual(pctEntry.data, pct)
        XCTAssertEqual(pctEntry.localExtraField, localExtraField)
        XCTAssertEqual(pctEntry.centralExtraField, centralExtraField)
        XCTAssertTrue(mapped.contains { $0.internalName == "[textures]\\pct\\demo.pct_header" })
    }

    func testDirectoryModMappingRecompressesEditedPCT() throws {
        let root = try temporaryDirectory(named: "workspace-directory-map-edited")
        let modRoot = root.appendingPathComponent("mods/pc", isDirectory: true)
        let original = makeSyntheticPCT(tableCount: 2)
        var edited = original
        edited.append(0x7F)
        try writeFile(root: modRoot, relativePath: "prebuild/textures/pct/demo.pct", data: edited)
        let sourcePak = try makePak(named: "pc.pak", entries: [
            "prebuild/textures/pct/demo.pct": original
        ])
        let entries = [
            PakWorkspaceSourceEntry(
                sourceEntryName: "prebuild/textures/pct/demo.pct",
                workspacePath: "mods/pc/prebuild/textures/pct/demo.pct",
                sha256: ModArchiveMapper.sha256Hex(uncompressedPayload: original)
            )
        ]

        let mapped = try ModArchiveMapper.mapDirectory(
            at: modRoot,
            archiveName: "pc.pak",
            sourceCache: sourcePak,
            sourceEntries: entries,
            workspaceRoot: root
        )

        let pctEntry = try XCTUnwrap(mapped.first { $0.internalName == "[textures]\\pct\\demo.pct" })
        XCTAssertNil(pctEntry.compressedPayload)
        XCTAssertEqual(pctEntry.data, edited)
    }

    func testDirectoryModMappingReportsInvalidPCTWithWorkspacePath() throws {
        let root = try temporaryDirectory(named: "workspace-directory-map-invalid-pct")
        let modRoot = root.appendingPathComponent("mods/pc", isDirectory: true)
        let original = makeSyntheticPCT(tableCount: 2)
        try writeFile(root: modRoot, relativePath: "prebuild/textures/pct/demo.pct", data: Data([0x01, 0x02]))
        let sourcePak = try makePak(named: "pc.pak", entries: [
            "prebuild/textures/pct/demo.pct": original
        ])
        let entries = [
            PakWorkspaceSourceEntry(
                sourceEntryName: "prebuild/textures/pct/demo.pct",
                workspacePath: "mods/pc/prebuild/textures/pct/demo.pct",
                sha256: ModArchiveMapper.sha256Hex(uncompressedPayload: original)
            )
        ]

        XCTAssertThrowsError(try ModArchiveMapper.mapDirectory(
            at: modRoot,
            archiveName: "pc.pak",
            sourceCache: sourcePak,
            sourceEntries: entries,
            workspaceRoot: root
        )) { error in
            XCTAssertTrue(String(describing: error).contains("mods/pc/prebuild/textures/pct/demo.pct"))
        }
    }

    func testModMergerWritesInlineTextureWorkspaceCandidateFromDirectorySources() throws {
        let workspace = try temporaryDirectory(named: "workspace-merge-core")
        let initial = PakWorkspacePaths.initialDirectory(root: workspace)
        try FileManager.default.createDirectory(at: initial, withIntermediateDirectories: true)
        let baseManifest = try LoadListBuilder.buildManifest(records: [
            LoadListRecord(
                manifestPath: "<media>\\classes\\trucks\\existing.xml",
                loaderType: "cls_loader",
                sourcePak: "initial.pak",
                phase: "CLASSES load"
            )
        ])
        try LoadListWriter.writeManifest(baseManifest, to: initial.appendingPathComponent("pak.load_list"))
        try writeFile(root: initial, relativePath: "initial.cache_block", data: Data("cache".utf8))
        try writeFile(root: initial, relativePath: "[media]/classes/trucks/existing.xml", data: Data("<Truck/>".utf8))
        try writeFile(root: initial, relativePath: "[ssl_cache]/initial_pak", data: Data("ssl".utf8))
        try writeFile(root: initial, relativePath: "[strings]/strings_english.str", data: stringTableData("BASE_KEY\t\t\"Base\""))

        let mod = try makePak(named: "pc.pak", entries: [
            "prebuild/textures/pct/new_texture.pct": makeSyntheticPCT(tableCount: 2)
        ])
        let modDir = PakWorkspacePaths.modDirectory(root: workspace, folderName: "pc")
        try PakModUnpacker.unpack(archiveURL: mod, toDirectory: modDir)
        let modArchive = try PakReader.readArchive(at: mod)
        let sourceEntries = try modArchive.entries.map {
            let workspacePath = "mods/pc/" + (try PakModPath.fileSystemRelativePath(forArchiveName: $0.name))
            return PakWorkspaceSourceEntry(
                sourceEntryName: $0.name,
                workspacePath: workspacePath,
                sha256: ModArchiveMapper.sha256Hex(uncompressedPayload: try PakReader.readUncompressedPayload(entry: $0, in: modArchive))
            )
        }
        let mapped = try ModArchiveMapper.mapDirectory(
            at: modDir,
            archiveName: "pc.pak",
            sourceCache: mod,
            sourceEntries: sourceEntries,
            workspaceRoot: workspace
        )
        let records = try WorkspaceInitialLoadListBuilder.records(fromInitialDirectory: initial, preservingFrom: baseManifest)
        let rebuiltManifest = try LoadListBuilder.buildManifest(records: records)
        let output = workspace.appendingPathComponent("candidate.pak")

        let result = try ModMerger.mergeWorkspaceInitial(
            initialDirectory: initial,
            baseManifest: rebuiltManifest,
            mappedEntries: mapped,
            outputInitialPak: output,
            reportURL: nil,
            verifyOutput: true
        )

        XCTAssertEqual(result.outputURL, output)
        let outputArchive = try PakReader.readArchive(at: output)
        XCTAssertTrue(outputArchive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct" })
        XCTAssertTrue(outputArchive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct_header" })
        XCTAssertTrue(try PakVerifier.verifySnowPakLayout(outputArchive).isEmpty)
    }
}
