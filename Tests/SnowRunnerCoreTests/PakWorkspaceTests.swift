import Foundation
import XCTest
@testable import SnowRunnerCore

final class PakWorkspaceTests: XCTestCase {
    func testWorkspaceManifestDecodesMissingEnabledAsTrue() throws {
        let json = Data("""
        {
          "version": 1,
          "initialSourcePath": "/game/initial.pak",
          "mods": [
            {
              "sourcePath": "/mods/demo.pak",
              "folderName": "demo",
              "archiveName": "demo.pak",
              "sourceCachePath": ".snowrunner/sources/demo.pak",
              "entries": []
            }
          ],
          "policy": {
            "textureMode": "inlineInitial",
            "allowInitialOverwrite": true
          }
        }
        """.utf8)

        let manifest = try JSONDecoder.pakWorkspace.decode(PakWorkspaceManifest.self, from: json)

        XCTAssertEqual(manifest.mods.count, 1)
        XCTAssertTrue(manifest.mods[0].enabled)
    }

    func testWorkspaceManifestEncodesEnabledState() throws {
        let manifest = PakWorkspaceManifest(
            version: 1,
            initialSourcePath: "/game/initial.pak",
            mods: [
                PakWorkspaceMod(
                    sourcePath: "/mods/demo.pak",
                    folderName: "demo",
                    archiveName: "demo.pak",
                    sourceCachePath: ".snowrunner/sources/demo.pak",
                    enabled: false,
                    entries: []
                )
            ],
            policy: PakWorkspacePolicy(textureMode: "inlineInitial", allowInitialOverwrite: true)
        )

        let data = try JSONEncoder.pakWorkspace.encode(manifest)
        let text = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder.pakWorkspace.decode(PakWorkspaceManifest.self, from: data)

        XCTAssertTrue(text.contains("\"enabled\" : false") || text.contains("\"enabled\": false"))
        XCTAssertFalse(decoded.mods[0].enabled)
    }

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

        XCTAssertEqual(PakWorkspacePaths.manifestURL(root: root).path, "/tmp/workspace/snowrunner-workspace.json")
        XCTAssertEqual(PakWorkspacePaths.initialDirectory(root: root).path, "/tmp/workspace/initial")
        XCTAssertEqual(PakWorkspacePaths.modsDirectory(root: root).path, "/tmp/workspace/mods")
        XCTAssertEqual(PakWorkspacePaths.buildInitialPak(root: root).path, "/tmp/workspace/build/initial.pak")
        XCTAssertEqual(PakWorkspacePaths.buildReport(root: root).path, "/tmp/workspace/build/workspace-build-report.md")
        XCTAssertEqual(PakWorkspacePaths.sourceCache(root: root, folderName: "demo").path, "/tmp/workspace/.snowrunner/sources/demo.pak")
    }

    func testWorkspaceLoadRejectsHiddenOnlyManifest() throws {
        let workspace = try temporaryDirectory(named: "workspace-hidden-manifest")
        let hiddenManifestURL = workspace.appendingPathComponent(".snowrunner-workspace.json")
        let manifest = PakWorkspaceManifest(
            version: 1,
            initialSourcePath: "/game/initial.pak",
            mods: [],
            policy: PakWorkspacePolicy(textureMode: "inlineInitial", allowInitialOverwrite: true)
        )
        try JSONEncoder.pakWorkspace.encode(manifest).write(to: hiddenManifestURL)

        XCTAssertThrowsError(try PakWorkspaceManager.loadManifest(workspace: workspace)) { error in
            XCTAssertEqual(
                error as? PakWorkspaceError,
                .missingManifest(workspace.appendingPathComponent("snowrunner-workspace.json").path)
            )
        }
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

    func testWorkspaceInitCreatesManifestAndUnpacksInitial() throws {
        let workspace = try temporaryDirectory(named: "workspace-init")

        let result = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)

        XCTAssertEqual(result.initialEntryCount, 10308)
        XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.manifestURL(root: workspace).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.initialDirectory(root: workspace).appendingPathComponent("pak.load_list").path))
        let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
        XCTAssertEqual(manifest.initialSourcePath, TestFixtures.initialPak.path)
        XCTAssertEqual(manifest.mods, [])
    }

    func testWorkspaceInitRejectsExistingNonEmptyInitial() throws {
        let workspace = try temporaryDirectory(named: "workspace-init-existing")
        try writeFile(root: PakWorkspacePaths.initialDirectory(root: workspace), relativePath: "file.txt", data: Data("x".utf8))

        XCTAssertThrowsError(try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)) { error in
            XCTAssertTrue(String(describing: error).contains("initial directory already exists"))
        }
    }

    func testWorkspaceInitAcceptsOriginalLayoutThatFailsSnowPakLayout() throws {
        XCTAssertEqual(CLI.run(arguments: ["pak", "verify-snowpak-layout", TestFixtures.initialPak.path]).exitCode, 1)
        let workspace = try temporaryDirectory(named: "workspace-init-original-layout")

        let result = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)

        XCTAssertEqual(result.initialEntryCount, 10308)
        XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.manifestURL(root: workspace).path))
    }

    func testWorkspaceAddModsUnpacksCachesAndRecordsManifest() throws {
        let workspace = try temporaryDirectory(named: "workspace-add-mod")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let mod = try makePak(named: "demo.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8)
        ])

        let result = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])

        XCTAssertEqual(result.addedMods.map(\.folderName), ["demo"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.modDirectory(root: workspace, folderName: "demo").appendingPathComponent("classes/trucks/demo.xml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.sourceCache(root: workspace, folderName: "demo").path))
        let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
        XCTAssertEqual(manifest.mods.count, 1)
        XCTAssertEqual(manifest.mods[0].entries.count, 1)
    }

    func testWorkspaceAddModPackagesImportsZipAsSingleCombinedMod() throws {
        let workspace = try temporaryDirectory(named: "workspace-add-zip-package")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let main = try makePak(named: "demo.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8)
        ])
        let texture = try makePak(named: "pc.pak", entries: [
            "prebuild/textures/pct/demo.pct": makeSyntheticPCT(tableCount: 2)
        ])
        let package = try makePak(named: "demo_download.zip", entries: [
            "demo.pak": Data(contentsOf: main),
            "pc.pak": Data(contentsOf: texture)
        ])

        let result = try PakWorkspaceManager.addModPackages(workspace: workspace, packages: [package])

        XCTAssertEqual(result.addedMods.map(\.folderName), ["demo"])
        let modRoot = PakWorkspacePaths.modDirectory(root: workspace, folderName: "demo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: modRoot.appendingPathComponent("classes/trucks/demo.xml").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: modRoot.appendingPathComponent("prebuild/textures/pct/demo.pct").path))
        let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
        XCTAssertEqual(manifest.mods.count, 1)
        XCTAssertEqual(manifest.mods[0].sourcePath, package.path)
        XCTAssertEqual(manifest.mods[0].archiveName, "demo.pak")
        XCTAssertEqual(manifest.mods[0].sourceCachePath, ".snowrunner/sources/demo.pak")
        XCTAssertEqual(Set(manifest.mods[0].entries.map(\.sourceEntryName)), [
            "classes/trucks/demo.xml",
            "prebuild/textures/pct/demo.pct"
        ])
        let cache = try PakReader.readArchive(at: PakWorkspacePaths.sourceCache(root: workspace, folderName: "demo"))
        XCTAssertEqual(Set(cache.entries.map(\.name)), [
            "classes/trucks/demo.xml",
            "prebuild/textures/pct/demo.pct"
        ])
    }

    func testWorkspaceAddModPackagesIgnoresZeroBytePlatformPaks() throws {
        let workspace = try temporaryDirectory(named: "workspace-add-zero-byte-platform-paks")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let main = try makePak(named: "TiresCargo.pak", entries: [
            "texts/strings_english.str": Data("KEY\t\t\"Value\"".utf8)
        ])
        let package = try makePak(named: "tc.zip", entries: [
            "TiresCargo.pak": Data(contentsOf: main),
            "pc.pak": Data(),
            "playstation_4.pak": Data(),
            "playstation_5.pak": Data()
        ])

        let result = try PakWorkspaceManager.addModPackages(workspace: workspace, packages: [package])

        XCTAssertEqual(result.addedMods.map(\.folderName), ["TiresCargo"])
        let modRoot = PakWorkspacePaths.modDirectory(root: workspace, folderName: "TiresCargo")
        XCTAssertTrue(FileManager.default.fileExists(atPath: modRoot.appendingPathComponent("texts/strings_english.str").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: modRoot.appendingPathComponent("pc.pak").path))
        let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
        XCTAssertEqual(manifest.mods[0].archiveName, "TiresCargo.pak")
        XCTAssertEqual(manifest.mods[0].entries.map(\.sourceEntryName), ["texts/strings_english.str"])
    }

    func testWorkspaceAddModPackagesAllowsByteIdenticalDuplicateSourcePaths() throws {
        let workspace = try temporaryDirectory(named: "workspace-add-identical-duplicate-package-path")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let main = try makePak(named: "demo.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8)
        ])
        let pct = makeSyntheticPCT(tableCount: 2)
        let firstTexture = try makePak(named: "pc.pak", entries: [
            "prebuild/textures/pct/demo.pct": pct
        ])
        let secondTexture = try makePak(named: "playstation_4.pak", entries: [
            "prebuild/textures/pct/demo.pct": pct
        ])
        let package = try makePak(named: "demo_multi_platform.zip", entries: [
            "demo.pak": Data(contentsOf: main),
            "pc.pak": Data(contentsOf: firstTexture),
            "playstation_4.pak": Data(contentsOf: secondTexture)
        ])

        _ = try PakWorkspaceManager.addModPackages(workspace: workspace, packages: [package])

        let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
        XCTAssertEqual(manifest.mods.count, 1)
        XCTAssertEqual(manifest.mods[0].entries.filter { $0.sourceEntryName == "prebuild/textures/pct/demo.pct" }.count, 1)
    }

    func testWorkspaceAddModPackagesRejectsDifferingDuplicateSourcePathsAtomically() throws {
        let workspace = try temporaryDirectory(named: "workspace-add-differing-duplicate-package-path")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let main = try makePak(named: "demo.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8)
        ])
        let firstTexture = try makePak(named: "pc.pak", entries: [
            "prebuild/textures/pct/demo.pct": makeSyntheticPCT(tableCount: 2)
        ])
        let secondTexture = try makePak(named: "playstation_4.pak", entries: [
            "prebuild/textures/pct/demo.pct": makeSyntheticPCT(tableCount: 3)
        ])
        let package = try makePak(named: "demo_multi_platform.zip", entries: [
            "demo.pak": Data(contentsOf: main),
            "pc.pak": Data(contentsOf: firstTexture),
            "playstation_4.pak": Data(contentsOf: secondTexture)
        ])

        XCTAssertThrowsError(try PakWorkspaceManager.addModPackages(workspace: workspace, packages: [package]))

        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.modDirectory(root: workspace, folderName: "demo").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.sourceCache(root: workspace, folderName: "demo").path))
        XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).mods, [])
    }

    func testWorkspaceAddModPackagesRejectsInvalidPackageShapesAtomically() throws {
        let workspace = try temporaryDirectory(named: "workspace-add-invalid-package-shapes")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let main = try makePak(named: "demo.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8)
        ])
        let secondMain = try makePak(named: "other.pak", entries: [
            "texts/strings_english.str": Data("KEY\t\t\"Value\"".utf8)
        ])
        let multipleMainPackage = try makePak(named: "multiple_main.zip", entries: [
            "demo.pak": Data(contentsOf: main),
            "other.pak": Data(contentsOf: secondMain)
        ])
        let unparseablePakPackage = try makePak(named: "invalid_pak.zip", entries: [
            "demo.pak": Data(contentsOf: main),
            "pc.pak": Data("not a pak".utf8)
        ])
        let unsupportedPak = try makePak(named: "unsupported.pak", entries: [
            "unknown/path.bin": Data([1, 2, 3])
        ])
        let unsupportedPackage = try makePak(named: "unsupported.zip", entries: [
            "unsupported.pak": Data(contentsOf: unsupportedPak)
        ])
        let looseFilePackage = try makePak(named: "loose.zip", entries: [
            "demo.pak": Data(contentsOf: main),
            "readme.txt": Data("not supported".utf8)
        ])

        for package in [multipleMainPackage, unparseablePakPackage, unsupportedPackage, looseFilePackage] {
            XCTAssertThrowsError(try PakWorkspaceManager.addModPackages(workspace: workspace, packages: [package]))
        }
        XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).mods, [])
    }

    func testWorkspaceAddModsRejectsDuplicateFolderName() throws {
        let workspace = try temporaryDirectory(named: "workspace-add-duplicate")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let first = try makePak(named: "demo.pak", entries: ["classes/trucks/a.xml": Data("<Truck/>".utf8)])
        let second = try makePak(named: "demo.pak", entries: ["classes/trucks/b.xml": Data("<Truck/>".utf8)])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first])

        XCTAssertThrowsError(try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [second]))
    }

    func testWorkspaceAddModsRejectsInvalidModWithoutCommittingAnyMod() throws {
        let workspace = try temporaryDirectory(named: "workspace-add-invalid-atomic")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let valid = try makePak(named: "valid.pak", entries: [
            "classes/trucks/valid.xml": Data("<Truck/>".utf8)
        ])
        let invalid = try makePak(named: "invalid.pak", entries: [
            "unknown/path.bin": Data([1, 2, 3])
        ])

        XCTAssertThrowsError(try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [valid, invalid]))

        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.modDirectory(root: workspace, folderName: "valid").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.modDirectory(root: workspace, folderName: "invalid").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.sourceCache(root: workspace, folderName: "valid").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.sourceCache(root: workspace, folderName: "invalid").path))
        let workspaceNames = try FileManager.default.contentsOfDirectory(atPath: workspace.path)
        XCTAssertFalse(workspaceNames.contains { $0.hasPrefix(".mod-") || $0.hasPrefix(".source-") })
        XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).mods, [])
    }

    func testWorkspaceAddModsIgnoresUnreferencedOrphanFolders() throws {
        let workspace = try temporaryDirectory(named: "workspace-add-orphan")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        try writeFile(
            root: PakWorkspacePaths.modDirectory(root: workspace, folderName: "demo"),
            relativePath: "orphan.txt",
            data: Data("orphan".utf8)
        )
        try writeFile(
            root: PakWorkspacePaths.sourcesDirectory(root: workspace),
            relativePath: "demo.pak",
            data: Data("orphan".utf8)
        )
        let mod = try makePak(named: "demo.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8)
        ])

        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])

        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.modDirectory(root: workspace, folderName: "demo").appendingPathComponent("orphan.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.modDirectory(root: workspace, folderName: "demo").appendingPathComponent("classes/trucks/demo.xml").path))
        XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).mods.map(\.folderName), ["demo"])
    }

    func testWorkspaceRemoveModDeletesFolderCacheAndManifestEntry() throws {
        let workspace = try temporaryDirectory(named: "workspace-remove-mod")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let mod = try makePak(named: "demo.pak", entries: ["classes/trucks/demo.xml": Data("<Truck/>".utf8)])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])

        try PakWorkspaceManager.removeMod(workspace: workspace, folderName: "demo")

        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.modDirectory(root: workspace, folderName: "demo").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.sourceCache(root: workspace, folderName: "demo").path))
        XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).mods, [])
    }

    func testWorkspaceRemoveModDeletesManifestAuthoredSourceCache() throws {
        let workspace = try temporaryDirectory(named: "workspace-remove-mod-custom-cache")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let mod = try makePak(named: "demo.pak", entries: ["classes/trucks/demo.xml": Data("<Truck/>".utf8)])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])
        var manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
        let customCachePath = ".snowrunner/custom-cache/demo-source.pak"
        let customCache = workspace.appendingPathComponent(customCachePath)
        try FileManager.default.createDirectory(at: customCache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: PakWorkspacePaths.sourceCache(root: workspace, folderName: "demo"), to: customCache)
        manifest.mods[0].sourceCachePath = customCachePath
        try JSONEncoder.pakWorkspace.encode(manifest).write(to: PakWorkspacePaths.manifestURL(root: workspace), options: .atomic)

        try PakWorkspaceManager.removeMod(workspace: workspace, folderName: "demo")

        XCTAssertFalse(FileManager.default.fileExists(atPath: customCache.path))
        XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).mods, [])
    }

    func testWorkspaceRemoveMissingModFailsClearly() throws {
        let workspace = try temporaryDirectory(named: "workspace-remove-missing")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)

        XCTAssertThrowsError(try PakWorkspaceManager.removeMod(workspace: workspace, folderName: "missing")) { error in
            XCTAssertTrue(String(describing: error).contains("missing"))
        }
    }

    func testWorkspaceSummaryReportsEnabledAndDisabledMods() throws {
        let workspace = try temporaryDirectory(named: "workspace-summary")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let active = try makePak(named: "active.pak", entries: ["classes/trucks/active.xml": Data("<Truck/>".utf8)])
        let disabled = try makePak(named: "disabled.pak", entries: ["classes/trucks/disabled.xml": Data("<Truck/>".utf8)])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [active, disabled])
        try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "disabled", enabled: false)

        let summary = try PakWorkspaceManager.summary(workspace: workspace)

        XCTAssertEqual(summary.workspace, workspace)
        XCTAssertEqual(summary.initialSourcePath, TestFixtures.initialPak.path)
        XCTAssertEqual(summary.mods.map(\.folderName), ["active", "disabled"])
        XCTAssertEqual(summary.mods.map(\.enabled), [true, false])
        XCTAssertEqual(summary.buildInitialPak, PakWorkspacePaths.buildInitialPak(root: workspace))
        XCTAssertEqual(summary.buildReport, PakWorkspacePaths.buildReport(root: workspace))
    }

    func testWorkspaceSummaryReportsPublishedBuildOutputAfterBuild() throws {
        let workspace = try temporaryDirectory(named: "workspace-summary-build-output")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)

        let beforeBuild = try PakWorkspaceManager.summary(workspace: workspace)
        XCTAssertNil(beforeBuild.buildOutput)

        _ = try PakWorkspaceManager.build(workspace: workspace)
        let afterBuild = try PakWorkspaceManager.summary(workspace: workspace)

        XCTAssertEqual(afterBuild.buildOutput?.initialPak, PakWorkspacePaths.buildInitialPak(root: workspace))
        XCTAssertEqual(afterBuild.buildOutput?.report, PakWorkspacePaths.buildReport(root: workspace))
        XCTAssertNotNil(afterBuild.buildOutput?.modifiedAt)
    }

    func testWorkspaceVerifyWritesNoBuildOutput() throws {
        let workspace = try temporaryDirectory(named: "workspace-verify")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)

        let result = try PakWorkspaceManager.verify(workspace: workspace)

        XCTAssertGreaterThan(result.plan.baseEntryCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildReport(root: workspace).path))
    }

    func testWorkspaceVerifyMergesCustomizationPresetWithoutBuildOutput() throws {
        let base = try makeSyntheticInitialPak(
            records: [],
            customizationPresetData: customizationPresetData([
                truckXML(name: "base", marker: "base")
            ])
        )
        let workspace = try temporaryDirectory(named: "workspace-verify-customization")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let mod = try makePak(named: "preset.pak", entries: [
            "classes/customization_presets/customization_preset.xml": customizationPresetData([
                truckXML(name: "mod", marker: "mod")
            ])
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])

        let result = try PakWorkspaceManager.verify(workspace: workspace)

        XCTAssertEqual(result.plan.customizationPresetMergeEntryCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildReport(root: workspace).path))
    }

    func testWorkspaceBuildPublishesVerifiedOutputAndReport() throws {
        let workspace = try temporaryDirectory(named: "workspace-build")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)

        let result = try PakWorkspaceManager.build(workspace: workspace)

        XCTAssertEqual(result.outputURL, PakWorkspacePaths.buildInitialPak(root: workspace))
        XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildReport(root: workspace).path))
        let archive = try PakReader.readArchive(at: PakWorkspacePaths.buildInitialPak(root: workspace))
        XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
        XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)
    }

    func testWorkspaceBuildWritesMergedCustomizationPresetAndReport() throws {
        let path = "[media]\\classes\\customization_presets\\customization_preset.xml"
        let base = try makeSyntheticInitialPak(
            records: [],
            customizationPresetData: customizationPresetData([
                truckXML(name: "base", marker: "base")
            ])
        )
        let workspace = try temporaryDirectory(named: "workspace-build-customization")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let mod = try makePak(named: "preset.pak", entries: [
            "classes/customization_presets/customization_preset.xml": customizationPresetData([
                truckXML(name: "mod", marker: "mod")
            ])
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])

        let result = try PakWorkspaceManager.build(workspace: workspace)

        XCTAssertEqual(result.plan.customizationPresetMergeEntryCount, 1)
        let archive = try PakReader.readArchive(at: PakWorkspacePaths.buildInitialPak(root: workspace))
        let entry = try XCTUnwrap(archive.entries.first { $0.name == path })
        let text = decodedUTF8(try PakReader.readUncompressedPayload(entry: entry, in: archive))
        XCTAssertTrue(text.contains("Name=\"base\""))
        XCTAssertTrue(text.contains("Name=\"mod\""))
        let report = try String(contentsOf: PakWorkspacePaths.buildReport(root: workspace), encoding: .utf8)
        XCTAssertTrue(report.contains("- customization preset merges: 1"))
    }

    func testWorkspaceBuildWithNoModsIncludesEditedInitialDirectory() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-build-edited-initial")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let initial = PakWorkspacePaths.initialDirectory(root: workspace)
        try writeFile(root: initial, relativePath: "[media]/classes/trucks/workspace_added.xml", data: Data("<Truck workspace=\"true\"/>".utf8))

        _ = try PakWorkspaceManager.build(workspace: workspace)

        let archive = try PakReader.readArchive(at: PakWorkspacePaths.buildInitialPak(root: workspace))
        XCTAssertTrue(archive.entries.contains { $0.name == "[media]\\classes\\trucks\\workspace_added.xml" })
        let manifestEntry = try XCTUnwrap(archive.entries.first { $0.name == LoadListConstants.manifestEntryName })
        let manifestData = try PakReader.readUncompressedPayload(entry: manifestEntry, in: archive)
        let manifest = try LoadListReader.readManifest(data: manifestData)
        XCTAssertTrue((manifest.recordsByPhase["CLASSES load"] ?? []).contains {
            $0.manifestPath == "<media>\\classes\\trucks\\workspace_added.xml"
                && $0.loaderType == "cls_loader"
                && $0.sourcePak == "initial.pak"
        })
    }

    func testWorkspaceBuildAllowsModOverwriteOfInitialByDefault() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-build-overwrite")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let mod = try makePak(named: "overwrite.pak", entries: [
            "classes/trucks/existing.xml": Data("<Truck mod=\"true\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])

        _ = try PakWorkspaceManager.build(workspace: workspace)

        let archive = try PakReader.readArchive(at: PakWorkspacePaths.buildInitialPak(root: workspace))
        let entry = try XCTUnwrap(archive.entries.first { $0.name == "[media]\\classes\\trucks\\existing.xml" })
        XCTAssertEqual(try PakReader.readUncompressedPayload(entry: entry, in: archive), Data("<Truck mod=\"true\"/>".utf8))
    }

    func testWorkspaceBuildUsesSelectedConflictResolutionCandidate() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-build-resolved-conflict")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
        try PakWorkspaceManager.resolveConflict(
            workspace: workspace,
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "second"
        )

        _ = try PakWorkspaceManager.build(workspace: workspace)

        let archive = try PakReader.readArchive(at: PakWorkspacePaths.buildInitialPak(root: workspace))
        let entry = try XCTUnwrap(archive.entries.first { $0.name == "[media]\\classes\\trucks\\same.xml" })
        XCTAssertEqual(
            try PakReader.readUncompressedPayload(entry: entry, in: archive),
            Data("<Truck id=\"second\"/>".utf8)
        )
    }

    func testWorkspaceBuildStillRejectsUnresolvedDifferentBytesConflict() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-build-unresolved-conflict")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

        XCTAssertThrowsError(try PakWorkspaceManager.build(workspace: workspace)) { error in
            XCTAssertTrue(String(describing: error).contains("[media]\\classes\\trucks\\same.xml"))
        }
    }

    func testWorkspaceBuildPrunesStaleResolutionAndUsesRemainingSingleCandidate() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-build-prune-stale-resolution")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
        try PakWorkspaceManager.resolveConflict(
            workspace: workspace,
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "second"
        )
        try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "first", enabled: false)

        _ = try PakWorkspaceManager.build(workspace: workspace)

        XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).conflictResolutions, [])
    }

    func testWorkspaceVerifyRejectsModToModConflict() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-mod-conflict")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

        XCTAssertThrowsError(try PakWorkspaceManager.verify(workspace: workspace)) { error in
            XCTAssertTrue(String(describing: error).contains("[media]\\classes\\trucks\\same.xml"))
        }
    }

    func testWorkspaceVerifyIgnoresDisabledConflictingMod() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-verify-disabled-conflict")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
        try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "second", enabled: false)

        let result = try PakWorkspaceManager.verify(workspace: workspace)

        XCTAssertGreaterThan(result.plan.mappedModEntryCount, 0)
    }

    func testWorkspaceManifestDefaultsConflictResolutionsForExistingManifest() throws {
        let workspace = try temporaryDirectory(named: "workspace-manifest-default-resolutions")
        let manifestURL = PakWorkspacePaths.manifestURL(root: workspace)
        let json = """
        {
          "initialSourcePath" : "/game/initial.pak",
          "mods" : [],
          "policy" : {
            "allowInitialOverwrite" : true,
            "textureMode" : "inlineInitial"
          },
          "version" : 1
        }
        """
        try json.data(using: .utf8)!.write(to: manifestURL)

        let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)

        XCTAssertEqual(manifest.conflictResolutions, [])
    }

    func testWorkspaceResolveConflictWritesSelectedModToManifest() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-resolve-conflict-manifest")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)

        try PakWorkspaceManager.resolveConflict(
            workspace: workspace,
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "first"
        )

        let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
        XCTAssertEqual(manifest.conflictResolutions, [
            PakWorkspaceConflictResolution(
                targetArchive: .initial,
                internalName: "[media]\\classes\\trucks\\same.xml",
                selectedMod: "first"
            )
        ])
    }

    func testWorkspaceClearConflictResolutionRemovesSavedChoice() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-clear-conflict-manifest")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        try PakWorkspaceManager.resolveConflict(
            workspace: workspace,
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "first"
        )

        try PakWorkspaceManager.clearConflictResolution(
            workspace: workspace,
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml"
        )

        let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
        XCTAssertEqual(manifest.conflictResolutions, [])
    }

    func testWorkspaceResolveConflictReplacesExistingChoiceForTarget() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-replace-conflict-manifest")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        try PakWorkspaceManager.resolveConflict(
            workspace: workspace,
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "first"
        )

        try PakWorkspaceManager.resolveConflict(
            workspace: workspace,
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "second"
        )

        let manifest = try PakWorkspaceManager.loadManifest(workspace: workspace)
        XCTAssertEqual(manifest.conflictResolutions, [
            PakWorkspaceConflictResolution(
                targetArchive: .initial,
                internalName: "[media]\\classes\\trucks\\same.xml",
                selectedMod: "second"
            )
        ])
    }

    func testWorkspaceQuickVerifyFlagsDuplicateTargetsWithDifferentBytes() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-conflict-different")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        let conflict = try XCTUnwrap(result.conflicts.first)
        XCTAssertEqual(conflict.targetPath, "[media]\\classes\\trucks\\same.xml")
        XCTAssertEqual(conflict.mods, ["first", "second"])
        XCTAssertFalse(conflict.isResolved)
    }

    func testWorkspaceQuickVerifyIgnoresMergeableCustomizationPresetDuplicates() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-customization-preset")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/customization_presets/customization_preset.xml": customizationPresetData([
                truckXML(name: "first_truck", marker: "first")
            ])
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/customization_presets/customization_preset.xml": customizationPresetData([
                truckXML(name: "second_truck", marker: "second")
            ])
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        XCTAssertEqual(result.conflicts, [])
    }

    func testWorkspaceQuickVerifyIgnoresMergeableStringTableDuplicates() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-string-table")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "texts/strings_english.str": stringTableData("""
            FIRST_KEY\t\t"First"
            """)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "texts/strings_english.str": stringTableData("""
            SECOND_KEY\t\t"Second"
            """)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        XCTAssertEqual(result.conflicts, [])
    }

    func testWorkspaceQuickVerifyFlagsDuplicateTargetsWithIdenticalBytes() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-conflict-identical")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"same\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"same\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        XCTAssertEqual(result.conflicts.map(\.targetPath), ["[media]\\classes\\trucks\\same.xml"])
        XCTAssertEqual(result.conflicts[0].mods, ["first", "second"])
    }

    func testWorkspaceQuickVerifyFlagsDuplicateNonInitialTargetsWithIdenticalBytes() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-conflict-shared-texture")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "ui/textures/foo.dds": Data([1, 2, 3, 4])
        ])
        let second = try makePak(named: "second.pak", entries: [
            "ui/textures/foo.dds": Data([1, 2, 3, 4])
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        let conflict = try XCTUnwrap(result.conflicts.first)
        XCTAssertEqual(conflict.targetPath, "[textures]\\foo.dds")
        XCTAssertEqual(conflict.mods, ["first", "second"])
        XCTAssertTrue(conflict.isByteIdentical)
    }

    func testWorkspaceQuickVerifyIncludesCandidateDetailsForUnresolvedConflict() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-conflict-details")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        let conflict = try XCTUnwrap(result.conflicts.first)
        XCTAssertFalse(conflict.isResolved)
        XCTAssertFalse(conflict.isByteIdentical)
        XCTAssertEqual(conflict.targetArchive, .initial)
        XCTAssertEqual(conflict.internalName, "[media]\\classes\\trucks\\same.xml")
        XCTAssertEqual(conflict.targetPath, "[media]\\classes\\trucks\\same.xml")
        XCTAssertEqual(conflict.mods, ["first", "second"])
        XCTAssertEqual(conflict.candidates.map(\.modFolderName), ["first", "second"])
        XCTAssertEqual(conflict.candidates.map(\.originalName), [
            "classes/trucks/same.xml",
            "classes/trucks/same.xml"
        ])
        XCTAssertTrue(conflict.candidates.allSatisfy { $0.byteSize > 0 })
        XCTAssertTrue(conflict.candidates.allSatisfy { $0.sha256.count == 64 })
        XCTAssertNil(conflict.selectedMod)
        XCTAssertEqual(result.unresolvedConflictCount, 1)
        XCTAssertEqual(result.resolvedConflictCount, 0)
    }

    func testWorkspaceQuickVerifyMarksValidResolutionAsResolved() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-resolved-conflict")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
        try PakWorkspaceManager.resolveConflict(
            workspace: workspace,
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "second"
        )

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        let conflict = try XCTUnwrap(result.conflicts.first)
        XCTAssertTrue(conflict.isResolved)
        XCTAssertEqual(conflict.selectedMod, "second")
        XCTAssertEqual(result.unresolvedConflictCount, 0)
        XCTAssertEqual(result.resolvedConflictCount, 1)
    }

    func testWorkspaceQuickVerifyPrunesResolutionWhenNoCurrentConflictRemains() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-prune-resolved-conflict")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
        try PakWorkspaceManager.resolveConflict(
            workspace: workspace,
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "second"
        )
        try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "first", enabled: false)

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        XCTAssertEqual(result.conflicts, [])
        XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).conflictResolutions, [])
    }

    func testWorkspaceQuickVerifyTreatsInvalidSavedChoiceAsUnresolved() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-invalid-choice")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
        try PakWorkspaceManager.resolveConflict(
            workspace: workspace,
            targetArchive: .initial,
            internalName: "[media]\\classes\\trucks\\same.xml",
            selectedMod: "missing"
        )

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        let conflict = try XCTUnwrap(result.conflicts.first)
        XCTAssertFalse(conflict.isResolved)
        XCTAssertNil(conflict.selectedMod)
        XCTAssertEqual(result.unresolvedConflictCount, 1)
        XCTAssertEqual(result.resolvedConflictCount, 0)
        XCTAssertEqual(try PakWorkspaceManager.loadManifest(workspace: workspace).conflictResolutions, [])
    }

    func testWorkspaceQuickVerifyIgnoresDisabledMods() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-disabled")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let first = try makePak(named: "first.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"first\"/>".utf8)
        ])
        let second = try makePak(named: "second.pak", entries: [
            "classes/trucks/same.xml": Data("<Truck id=\"second\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [first, second])
        try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "second", enabled: false)

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        XCTAssertEqual(result.conflicts, [])
    }

    func testWorkspaceQuickVerifyIgnoresModOverInitialReplacement() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-quick-over-initial")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let replacement = try makePak(named: "replacement.pak", entries: [
            "classes/trucks/existing.xml": Data("<Truck id=\"replacement\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [replacement])

        let result = try PakWorkspaceManager.quickVerify(workspace: workspace)

        XCTAssertEqual(result.conflicts, [])
    }

    func testWorkspaceBuildIgnoresDisabledModPayload() throws {
        let base = try makeSyntheticInitialPak()
        let workspace = try temporaryDirectory(named: "workspace-build-disabled")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: base)
        let active = try makePak(named: "active.pak", entries: [
            "classes/trucks/active.xml": Data("<Truck id=\"active\"/>".utf8)
        ])
        let disabled = try makePak(named: "disabled.pak", entries: [
            "classes/trucks/disabled.xml": Data("<Truck id=\"disabled\"/>".utf8)
        ])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [active, disabled])
        try PakWorkspaceManager.setModEnabled(workspace: workspace, folderName: "disabled", enabled: false)

        _ = try PakWorkspaceManager.build(workspace: workspace)

        let archive = try PakReader.readArchive(at: PakWorkspacePaths.buildInitialPak(root: workspace))
        XCTAssertTrue(archive.entries.contains { $0.name == "[media]\\classes\\trucks\\active.xml" })
        XCTAssertFalse(archive.entries.contains { $0.name == "[media]\\classes\\trucks\\disabled.xml" })
    }

    func testWorkspaceBuildFailsWhenSourceCacheMissing() throws {
        let workspace = try temporaryDirectory(named: "workspace-missing-cache")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let mod = try makePak(named: "demo.pak", entries: ["classes/trucks/demo.xml": Data("<Truck/>".utf8)])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])
        try FileManager.default.removeItem(at: PakWorkspacePaths.sourceCache(root: workspace, folderName: "demo"))

        XCTAssertThrowsError(try PakWorkspaceManager.verify(workspace: workspace)) { error in
            XCTAssertTrue(String(describing: error).contains("cached source PAK"))
        }
    }

    func testWorkspaceBuildFailureLeavesPreviousOutputAndReportIntact() throws {
        let workspace = try temporaryDirectory(named: "workspace-build-failure-preserves-output")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        _ = try PakWorkspaceManager.build(workspace: workspace)
        let previousPak = try Data(contentsOf: PakWorkspacePaths.buildInitialPak(root: workspace))
        let previousReport = try String(contentsOf: PakWorkspacePaths.buildReport(root: workspace), encoding: .utf8)

        let mod = try makePak(named: "demo.pak", entries: ["classes/trucks/demo.xml": Data("<Truck/>".utf8)])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])
        try FileManager.default.removeItem(at: PakWorkspacePaths.sourceCache(root: workspace, folderName: "demo"))

        XCTAssertThrowsError(try PakWorkspaceManager.build(workspace: workspace))
        XCTAssertEqual(try Data(contentsOf: PakWorkspacePaths.buildInitialPak(root: workspace)), previousPak)
        XCTAssertEqual(try String(contentsOf: PakWorkspacePaths.buildReport(root: workspace), encoding: .utf8), previousReport)
    }

    func testWorkspaceBuildReportPublishFailureRollsBackPublishedPak() throws {
        let workspace = try temporaryDirectory(named: "workspace-build-report-publish-rollback")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        _ = try PakWorkspaceManager.build(workspace: workspace)
        let previousPak = try Data(contentsOf: PakWorkspacePaths.buildInitialPak(root: workspace))
        let previousReport = try String(contentsOf: PakWorkspacePaths.buildReport(root: workspace), encoding: .utf8)

        let mod = try makePak(named: "demo.pak", entries: ["classes/trucks/demo.xml": Data("<Truck/>".utf8)])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])
        PakWorkspaceManager.afterInitialBuildPakPublishHook = {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { PakWorkspaceManager.afterInitialBuildPakPublishHook = nil }

        XCTAssertThrowsError(try PakWorkspaceManager.build(workspace: workspace))
        XCTAssertEqual(try Data(contentsOf: PakWorkspacePaths.buildInitialPak(root: workspace)), previousPak)
        XCTAssertEqual(try String(contentsOf: PakWorkspacePaths.buildReport(root: workspace), encoding: .utf8), previousReport)
    }

    func testWorkspaceVerifyReportsMissingModDirectoryWithWorkspacePath() throws {
        let workspace = try temporaryDirectory(named: "workspace-missing-mod-dir")
        _ = try PakWorkspaceManager.initialize(workspace: workspace, initialPak: TestFixtures.initialPak)
        let mod = try makePak(named: "demo.pak", entries: ["classes/trucks/demo.xml": Data("<Truck/>".utf8)])
        _ = try PakWorkspaceManager.addMods(workspace: workspace, modPaks: [mod])
        try FileManager.default.removeItem(at: PakWorkspacePaths.modDirectory(root: workspace, folderName: "demo"))

        XCTAssertThrowsError(try PakWorkspaceManager.verify(workspace: workspace)) { error in
            XCTAssertTrue(String(describing: error).contains("mods/demo"))
        }
    }
}
