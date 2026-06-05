import Foundation
import XCTest
@testable import SnowRunnerTool

final class ModMergerTests: XCTestCase {
    func testMergerRequiresOverwriteForBaseCollision() throws {
        let base = try makeSyntheticInitialPak()
        let mod = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/existing.xml": Data("<Truck mod=\"true\"/>".utf8)
        ])
        let output = try temporaryDirectory(named: "merge-output")
            .appendingPathComponent("initial.merged.pak")

        XCTAssertThrowsError(try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            modPaks: [mod],
            options: ModMergeOptions(allowOverwrite: false)
        )) { error in
            guard case ModMergeError.overwriteRequired = error else {
                XCTFail("expected overwriteRequired, got \(error)")
                return
            }
        }
    }

    func testMergerWritesVerifiedMergedPak() throws {
        let base = try makeSyntheticInitialPak()
        let baseTextures = try makeSyntheticSharedTexturesPak(entries: [
            "[textures]\\pct\\existing_texture.pct_base": Data([0])
        ])
        let baseSharedTextures = try makeSyntheticHighSharedTexturesPak(entries: [:])
        let mod = try makePak(named: "main-mod.pak", entries: [
            "classes/trucks/existing.xml": Data("<Truck mod=\"true\"/>".utf8),
            "prebuild/meshes/new_mesh": Data([1, 2, 3]),
            "ui/textures/icon.png": Data([4, 5, 6]),
            "texts/strings_english.str": stringTableData("""
            BASE_KEY\t\t"Mod"
            MOD_KEY\t\t"Added"
            """)
        ])
        let pc = try makePak(named: "pc.pak", entries: [
            "prebuild/textures/pct/new_texture.pct": makeSyntheticPCT(tableCount: 11)
        ])
        let output = try temporaryDirectory(named: "merge-output")
            .appendingPathComponent("initial.merged.pak")
        let outputTextures = try temporaryDirectory(named: "merge-textures-output")
            .appendingPathComponent("shared_textures_base.merged.pak")
        let outputSharedTextures = try temporaryDirectory(named: "merge-shared-textures-output")
            .appendingPathComponent("shared_textures.merged.pak")

        let result = try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            baseSharedTexturesPak: baseTextures,
            outputSharedTexturesPak: outputTextures,
            baseHighSharedTexturesPak: baseSharedTextures,
            outputHighSharedTexturesPak: outputSharedTextures,
            modPaks: [mod, pc],
            options: ModMergeOptions(allowOverwrite: true)
        )

        XCTAssertEqual(result.plan.mappedModEntryCount, 6)
        XCTAssertEqual(result.plan.collisions, [
            "[media]\\classes\\trucks\\existing.xml"
        ])
        XCTAssertEqual(result.plan.netNewOuterPakEntryCount, 1)
        XCTAssertEqual(result.plan.stringMergeEntryCount, 1)
        XCTAssertEqual(result.plan.textureCollisions, [])
        XCTAssertEqual(result.plan.netNewTexturePakEntryCount, 1)
        XCTAssertEqual(result.plan.netNewSharedTexturePakEntryCount, 2)
        XCTAssertEqual(result.plan.loadListCandidateRecords.count, 4)
        XCTAssertEqual(result.plan.textureLoadListRecordCount, 2)
        XCTAssertEqual(result.plan.netNewLoadListRecordCount, 3)

        let archive = try PakReader.readArchive(at: output)
        XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
        XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)
        XCTAssertTrue(archive.entries.contains { $0.name == "[meshes]\\new_mesh" })
        XCTAssertFalse(archive.entries.contains { $0.name.hasPrefix("[textures]\\") })
        XCTAssertTrue(archive.entries.contains { $0.name == "[strings]\\strings_english.str" })
        let stringEntry = try XCTUnwrap(archive.entries.first { $0.name == "[strings]\\strings_english.str" })
        let stringData = try PakReader.readUncompressedPayload(entry: stringEntry, in: archive)
        XCTAssertEqual(decodedStringTable(stringData), """
        KEEP_KEY\t\t"Keep"
        BASE_KEY\t\t"Mod"
        MOD_KEY\t\t"Added"
        """)

        let textureArchive = try PakReader.readArchive(at: outputTextures)
        XCTAssertTrue(textureArchive.entries.contains { $0.name == "[textures]\\pct\\existing_texture.pct_base" })
        XCTAssertTrue(textureArchive.entries.contains { $0.name == "[textures]\\icon.png" })

        let sharedTextureArchive = try PakReader.readArchive(at: outputSharedTextures)
        XCTAssertTrue(sharedTextureArchive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct" })
        XCTAssertTrue(sharedTextureArchive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct_header" })

        let manifestEntry = try XCTUnwrap(archive.entries.first { $0.name == LoadListConstants.manifestEntryName })
        let manifestData = try PakReader.readUncompressedPayload(entry: manifestEntry, in: archive)
        let manifest = try LoadListReader.readManifest(data: manifestData)
        let meshRecords = manifest.recordsByPhase["MESH load"] ?? []
        XCTAssertTrue(meshRecords.contains {
            $0.manifestPath == "<meshes>\\new_mesh"
                && $0.loaderType == "mesh_loader"
                && $0.sourcePak == "initial.pak"
        })
        let textureRecords = manifest.recordsByPhase["TEXTURE load"] ?? []
        XCTAssertTrue(textureRecords.contains {
            $0.manifestPath == "<textures>\\pct\\new_texture.pct_header"
                && $0.loaderType == "pct_mr2_header"
                && $0.sourcePak == "shared_textures.pak"
        })
        XCTAssertTrue(textureRecords.contains {
            $0.manifestPath == "<textures>\\pct\\new_texture.pct_header"
                && $0.loaderType == "pct_faces"
                && $0.sourcePak == "shared_textures.pak"
        })
        let skippedRecords = manifest.phaseOrder.flatMap { manifest.recordsByPhase[$0] ?? [] }
            .filter { $0.manifestPath.contains("<ui>") || $0.manifestPath.contains("<strings>") }
        XCTAssertTrue(skippedRecords.isEmpty)
    }

    func testMergerRequiresSharedTextureOutputsWhenPCTTextureEntriesExist() throws {
        let base = try makeSyntheticInitialPak()
        let pc = try makePak(named: "renamed_pc_archive.pak", entries: [
            "prebuild/textures/pct/new_texture.pct": makeSyntheticPCT(tableCount: 10)
        ])
        let output = try temporaryDirectory(named: "merge-missing-texture-output")
            .appendingPathComponent("initial.merged.pak")

        XCTAssertThrowsError(try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            modPaks: [pc],
            options: ModMergeOptions(allowOverwrite: true)
        )) { error in
            guard case ModMergeError.missingSharedTextureOutput = error else {
                XCTFail("expected missingSharedTextureOutput, got \(error)")
                return
            }
        }
    }

    func testExperimentalModTexturePakWritesAllTextureEntriesAndRedirectsLoadList() throws {
        let base = try makeSyntheticInitialPak(records: [
            LoadListRecord(
                manifestPath: "<textures>\\pct\\existing_texture.pct_header",
                loaderType: "pct_mr2_header",
                sourcePak: "shared_textures.pak",
                phase: "TEXTURE load"
            ),
            LoadListRecord(
                manifestPath: "<textures>\\pct\\existing_texture.pct_header",
                loaderType: "pct_faces",
                sourcePak: "shared_textures.pak",
                phase: "TEXTURE load"
            )
        ])
        let mod = try makePak(named: "main-mod.pak", entries: [
            "ui/textures/icon.png": Data([4, 5, 6])
        ])
        let pc = try makePak(named: "renamed_pc_archive.pak", entries: [
            "prebuild/textures/pct/existing_texture.pct": makeSyntheticPCT(tableCount: 11),
            "prebuild/textures/pct/new_texture.pct": makeSyntheticPCT(tableCount: 12)
        ])
        let output = try temporaryDirectory(named: "merge-output")
            .appendingPathComponent("initial.merged.pak")
        let outputModTextures = try temporaryDirectory(named: "merge-mod-textures-output")
            .appendingPathComponent("mod_textures.pak")

        let result = try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            modPaks: [mod, pc],
            options: ModMergeOptions(
                allowOverwrite: true,
                experimentalModTexturesOutputURL: outputModTextures
            )
        )

        XCTAssertNil(result.outputTexturesURL)
        XCTAssertEqual(result.outputSharedTexturesURL, outputModTextures)
        XCTAssertEqual(result.plan.netNewTexturePakEntryCount, 1)
        XCTAssertEqual(result.plan.netNewSharedTexturePakEntryCount, 4)
        XCTAssertEqual(result.plan.textureLoadListRecordCount, 4)
        XCTAssertEqual(
            result.plan.loadListSourceOverrides,
            [
                ModLoadListSourceOverride(
                    manifestPath: "<textures>\\pct\\existing_texture.pct_header",
                    previousSourcePak: "shared_textures.pak",
                    newSourcePak: "mod_textures.pak"
                ),
                ModLoadListSourceOverride(
                    manifestPath: "<textures>\\pct\\existing_texture.pct_header",
                    previousSourcePak: "shared_textures.pak",
                    newSourcePak: "mod_textures.pak"
                )
            ]
        )

        let modTextureArchive = try PakReader.readArchive(at: outputModTextures)
        XCTAssertTrue(modTextureArchive.entries.contains { $0.name == "[textures]\\icon.png" })
        XCTAssertTrue(modTextureArchive.entries.contains { $0.name == "[textures]\\pct\\existing_texture.pct" })
        XCTAssertTrue(modTextureArchive.entries.contains { $0.name == "[textures]\\pct\\existing_texture.pct_header" })
        XCTAssertTrue(modTextureArchive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct" })
        XCTAssertTrue(modTextureArchive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct_header" })
        try PakReader.validatePayloadCRCs(in: modTextureArchive)

        let archive = try PakReader.readArchive(at: output)
        let manifestEntry = try XCTUnwrap(archive.entries.first { $0.name == LoadListConstants.manifestEntryName })
        let manifestData = try PakReader.readUncompressedPayload(entry: manifestEntry, in: archive)
        let manifest = try LoadListReader.readManifest(data: manifestData)
        let textureRecords = manifest.recordsByPhase["TEXTURE load"] ?? []
        XCTAssertEqual(
            textureRecords.filter {
                $0.manifestPath == "<textures>\\pct\\existing_texture.pct_header"
                    && $0.sourcePak == "mod_textures.pak"
            }.count,
            2
        )
        XCTAssertFalse(textureRecords.contains {
            $0.manifestPath == "<textures>\\pct\\existing_texture.pct_header"
                && $0.sourcePak == "shared_textures.pak"
        })
        XCTAssertTrue(textureRecords.contains {
            $0.manifestPath == "<textures>\\pct\\new_texture.pct_header"
                && $0.loaderType == "pct_mr2_header"
                && $0.sourcePak == "mod_textures.pak"
        })
        XCTAssertTrue(textureRecords.contains {
            $0.manifestPath == "<textures>\\pct\\new_texture.pct_header"
                && $0.loaderType == "pct_faces"
                && $0.sourcePak == "mod_textures.pak"
        })
    }

    func testExperimentalInlineTexturesWritesTextureEntriesIntoInitialPak() throws {
        let base = try makeSyntheticInitialPak(records: [
            LoadListRecord(
                manifestPath: "<textures>\\pct\\existing_texture.pct_header",
                loaderType: "pct_mr2_header",
                sourcePak: "shared_textures.pak",
                phase: "TEXTURE load"
            ),
            LoadListRecord(
                manifestPath: "<textures>\\pct\\existing_texture.pct_header",
                loaderType: "pct_faces",
                sourcePak: "shared_textures.pak",
                phase: "TEXTURE load"
            )
        ])
        let mod = try makePak(named: "main-mod.pak", entries: [
            "ui/textures/icon.png": Data([4, 5, 6])
        ])
        let pc = try makePak(named: "renamed_pc_archive.pak", entries: [
            "prebuild/textures/pct/existing_texture.pct": makeSyntheticPCT(tableCount: 11),
            "prebuild/textures/pct/new_texture.pct": makeSyntheticPCT(tableCount: 12)
        ])
        let output = try temporaryDirectory(named: "merge-output")
            .appendingPathComponent("initial.merged.pak")

        let result = try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            modPaks: [mod, pc],
            options: ModMergeOptions(
                allowOverwrite: true,
                experimentalInlineTextures: true
            )
        )

        XCTAssertNil(result.outputTexturesURL)
        XCTAssertNil(result.outputSharedTexturesURL)
        XCTAssertEqual(result.plan.netNewOuterPakEntryCount, 5)
        XCTAssertEqual(result.plan.textureLoadListRecordCount, 4)
        XCTAssertEqual(
            result.plan.loadListSourceOverrides,
            [
                ModLoadListSourceOverride(
                    manifestPath: "<textures>\\pct\\existing_texture.pct_header",
                    previousSourcePak: "shared_textures.pak",
                    newSourcePak: "initial.pak"
                ),
                ModLoadListSourceOverride(
                    manifestPath: "<textures>\\pct\\existing_texture.pct_header",
                    previousSourcePak: "shared_textures.pak",
                    newSourcePak: "initial.pak"
                )
            ]
        )

        let archive = try PakReader.readArchive(at: output)
        XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
        XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)
        XCTAssertTrue(archive.entries.contains { $0.name == "[textures]\\icon.png" })
        XCTAssertTrue(archive.entries.contains { $0.name == "[textures]\\pct\\existing_texture.pct" })
        XCTAssertTrue(archive.entries.contains { $0.name == "[textures]\\pct\\existing_texture.pct_header" })
        XCTAssertTrue(archive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct" })
        XCTAssertTrue(archive.entries.contains { $0.name == "[textures]\\pct\\new_texture.pct_header" })

        let manifestEntry = try XCTUnwrap(archive.entries.first { $0.name == LoadListConstants.manifestEntryName })
        let manifestData = try PakReader.readUncompressedPayload(entry: manifestEntry, in: archive)
        let manifest = try LoadListReader.readManifest(data: manifestData)
        let textureRecords = manifest.recordsByPhase["TEXTURE load"] ?? []
        XCTAssertEqual(
            textureRecords.filter {
                $0.manifestPath == "<textures>\\pct\\existing_texture.pct_header"
                    && $0.sourcePak == "initial.pak"
            }.count,
            2
        )
        XCTAssertFalse(textureRecords.contains {
            $0.manifestPath == "<textures>\\pct\\existing_texture.pct_header"
                && $0.sourcePak == "shared_textures.pak"
        })
        XCTAssertTrue(textureRecords.contains {
            $0.manifestPath == "<textures>\\pct\\new_texture.pct_header"
                && $0.loaderType == "pct_mr2_header"
                && $0.sourcePak == "initial.pak"
        })
        XCTAssertTrue(textureRecords.contains {
            $0.manifestPath == "<textures>\\pct\\new_texture.pct_header"
                && $0.loaderType == "pct_faces"
                && $0.sourcePak == "initial.pak"
        })
    }

    func testMergerMergesStringCollisionWithoutAllowOverwrite() throws {
        let base = try makeSyntheticInitialPak()
        let mod = try makePak(named: "text-mod.pak", entries: [
            "texts/strings_english.str": stringTableData("""
            BASE_KEY\t\t"Mod"
            NEW_KEY\t\t"New"
            """)
        ])
        let output = try temporaryDirectory(named: "merge-string-output")
            .appendingPathComponent("initial.merged.pak")

        let result = try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            modPaks: [mod],
            options: ModMergeOptions(allowOverwrite: false)
        )

        XCTAssertEqual(result.plan.collisions, [])
        XCTAssertEqual(result.plan.stringMergeEntryCount, 1)
        XCTAssertEqual(result.plan.netNewOuterPakEntryCount, 0)

        let archive = try PakReader.readArchive(at: output)
        let stringEntry = try XCTUnwrap(archive.entries.first { $0.name == "[strings]\\strings_english.str" })
        let stringData = try PakReader.readUncompressedPayload(entry: stringEntry, in: archive)
        XCTAssertEqual(decodedStringTable(stringData), """
        KEEP_KEY\t\t"Keep"
        BASE_KEY\t\t"Mod"
        NEW_KEY\t\t"New"
        """)
    }

    func testMergerPreservesBaseKeysWhenMergingTextFixture() throws {
        guard FileManager.default.fileExists(atPath: TestFixtures.initialPak.path),
              let textPak = TestFixtures.optionalTextPak() else {
            throw XCTSkip("initial.pak or text.pak fixture is not present")
        }
        let output = try temporaryDirectory(named: "merge-text-fixture-output")
            .appendingPathComponent("initial.merged.pak")

        let result = try ModMerger.merge(
            baseInitialPak: TestFixtures.initialPak,
            outputInitialPak: output,
            modPaks: [textPak],
            options: ModMergeOptions(allowOverwrite: false)
        )

        XCTAssertEqual(result.plan.collisions, [])
        XCTAssertEqual(result.plan.stringMergeEntryCount, 13)
        XCTAssertEqual(result.plan.netNewOuterPakEntryCount, 0)

        let archive = try PakReader.readArchive(at: output)
        let stringEntry = try XCTUnwrap(archive.entries.first { $0.name == "[strings]\\strings_english.str" })
        let stringData = try PakReader.readUncompressedPayload(entry: stringEntry, in: archive)
        let stringText = decodedStringTable(stringData)
        XCTAssertGreaterThan(stringData.count, 1_000_000)
        XCTAssertTrue(stringText.contains("UI_COMMON_BRICK_CARCASS\t"))
        XCTAssertTrue(stringText.contains("UI_TIRE_HIGHWAY_DOUBLE_1_NAME\t"))
    }

    func testMergerRequiresOverwriteForSharedTextureCollision() throws {
        let base = try makeSyntheticInitialPak()
        let baseSharedTextures = try makeSyntheticHighSharedTexturesPak(entries: [
            "[textures]\\pct\\new_texture.pct": Data([1])
        ])
        let pc = try makePak(named: "renamed_pc_archive.pak", entries: [
            "prebuild/textures/pct/new_texture.pct": makeSyntheticPCT(tableCount: 11)
        ])
        let output = try temporaryDirectory(named: "merge-output")
            .appendingPathComponent("initial.merged.pak")
        let outputSharedTextures = try temporaryDirectory(named: "merge-shared-textures-output")
            .appendingPathComponent("shared_textures.merged.pak")

        XCTAssertThrowsError(try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            baseHighSharedTexturesPak: baseSharedTextures,
            outputHighSharedTexturesPak: outputSharedTextures,
            modPaks: [pc],
            options: ModMergeOptions(allowOverwrite: false)
        )) { error in
            guard case let ModMergeError.overwriteRequired(paths) = error else {
                XCTFail("expected overwriteRequired, got \(error)")
                return
            }
            XCTAssertEqual(paths, ["[textures]\\pct\\new_texture.pct"])
        }
    }

    func testMergerDryRunDoesNotWriteInitialOrTextureOutput() throws {
        let base = try makeSyntheticInitialPak()
        let baseSharedTextures = try makeSyntheticHighSharedTexturesPak(entries: [:])
        let pc = try makePak(named: "renamed_pc_archive.pak", entries: [
            "prebuild/textures/pct/new_texture.pct": makeSyntheticPCT(tableCount: 10)
        ])
        let output = try temporaryDirectory(named: "merge-output")
            .appendingPathComponent("initial.merged.pak")
        let outputSharedTextures = try temporaryDirectory(named: "merge-shared-textures-output")
            .appendingPathComponent("shared_textures.merged.pak")

        let result = try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            baseHighSharedTexturesPak: baseSharedTextures,
            outputHighSharedTexturesPak: outputSharedTextures,
            modPaks: [pc],
            options: ModMergeOptions(allowOverwrite: true, dryRun: true)
        )

        XCTAssertNil(result.outputURL)
        XCTAssertNil(result.outputTexturesURL)
        XCTAssertNil(result.outputSharedTexturesURL)
        XCTAssertEqual(result.plan.textureLoadListRecordCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputSharedTextures.path))
    }

    func testMergerReportCountsTextureLoadListRecordsSeparately() throws {
        let plan = ModMergePlan(
            baseEntryCount: 1,
            mappedModEntryCount: 2,
            netNewOuterPakEntryCount: 0,
            collisions: [],
            textureBaseEntryCount: 1,
            netNewTexturePakEntryCount: 2,
            textureCollisions: [],
            sharedTextureEntryCount: 1,
            netNewSharedTexturePakEntryCount: 2,
            sharedTextureCollisions: [],
            stringMergeEntryCount: 0,
            duplicateIdenticalMappedNames: [],
            loadListSourceOverrides: [],
            loadListCandidateRecords: [
                LoadListRecord(
                    manifestPath: "<media>\\classes\\trucks\\new.xml",
                    loaderType: "cls_loader",
                    sourcePak: "initial.pak",
                    phase: "CLASSES load"
                ),
                LoadListRecord(
                    manifestPath: "<textures>\\pct\\new_texture.pct_header",
                    loaderType: "pct_mr2_header",
                    sourcePak: "shared_textures.pak",
                    phase: "TEXTURE load"
                ),
                LoadListRecord(
                    manifestPath: "<textures>\\pct\\new_texture.pct_header",
                    loaderType: "pct_faces",
                    sourcePak: "shared_textures.pak",
                    phase: "TEXTURE load"
                )
            ],
            netNewLoadListRecordCount: 3,
            texturesInInitial: false
        )
        let report = ModMergeReporter.stdout(result: ModMergeResult(
            plan: plan,
            outputURL: nil,
            outputTexturesURL: nil,
            outputSharedTexturesURL: nil,
            writtenEntryCount: nil,
            writtenTextureEntryCount: nil,
            writtenSharedTextureEntryCount: nil
        ))

        XCTAssertTrue(report.contains("texture load-list records: 2"))
    }
}
