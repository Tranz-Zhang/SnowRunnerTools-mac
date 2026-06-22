import Foundation
import XCTest
@testable import SnowRunnerCore

final class CLITests: XCTestCase {
    func testNoArgumentsPrintsUsageAndFails() {
        let result = CLI.run(arguments: [])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool"))
    }

    func testUnknownCommandFails() {
        let result = CLI.run(arguments: ["unknown"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Unknown command"))
    }

    func testPakUnpackModAndPackModCommands() throws {
        let input = try makePak(named: "cli-main-mod.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8),
            "prebuild/meshes/demo_mesh": Data([1, 2, 3])
        ])
        let unpacked = try temporaryDirectory(named: "cli-mod-unpack")
        let output = unpacked.deletingLastPathComponent().appendingPathComponent("cli-mod-output.pak")

        let unpackResult = CLI.run(arguments: ["pak", "unpack-mod", input.path, unpacked.path])
        XCTAssertEqual(unpackResult.exitCode, 0)
        XCTAssertTrue(unpackResult.stdout.contains("unpacked 2 mod entries"))

        let packResult = CLI.run(arguments: ["pak", "pack-mod", unpacked.path, output.path])
        XCTAssertEqual(packResult.exitCode, 0)
        XCTAssertTrue(packResult.stdout.contains("packed 2 mod entries"))

        let archive = try PakReader.readArchive(at: output)
        XCTAssertEqual(archive.entries.map(\.name), [
            "classes/trucks/demo.xml",
            "prebuild/meshes/demo_mesh"
        ])
    }

    func testPakUnpackStillRejectsForwardSlashModArchive() throws {
        let input = try makePak(named: "cli-main-mod.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8)
        ])
        let unpacked = try temporaryDirectory(named: "cli-initial-unpack-mod-input")

        let result = CLI.run(arguments: ["pak", "unpack", input.path, unpacked.path])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("Invalid internal PAK name"))
    }

    func testPakModCommandUsageErrors() {
        let unpackResult = CLI.run(arguments: ["pak", "unpack-mod"])
        XCTAssertEqual(unpackResult.exitCode, 2)
        XCTAssertTrue(unpackResult.stderr.contains("Usage: snowrunner-tool pak unpack-mod <mod.pak> <dir>"))

        let packResult = CLI.run(arguments: ["pak", "pack-mod"])
        XCTAssertEqual(packResult.exitCode, 2)
        XCTAssertTrue(packResult.stderr.contains("Usage: snowrunner-tool pak pack-mod <dir> <mod.pak>"))
    }

    func testInspectCommandReportsEntryCounts() {
        let result = CLI.run(arguments: ["pak", "inspect", TestFixtures.initialPak.path])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("entries: 10308"))
        XCTAssertTrue(result.stdout.contains("stored: 8325"))
        XCTAssertTrue(result.stdout.contains("deflated: 1983"))
    }

    func testVerifyBasicCommandPassesFixture() {
        let result = CLI.run(arguments: ["pak", "verify-basic", TestFixtures.initialPak.path])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("PASS"))
    }

    func testVerifySnowPakLayoutCommandReturnsFailureForOriginalPak() {
        let result = CLI.run(arguments: ["pak", "verify-snowpak-layout", TestFixtures.initialPak.path])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains("entry-order") || result.stdout.contains("non-load-list-stored-entry"))
    }

    func testCLIPackWritesVerifiableArchive() throws {
        let unpacked = try temporaryDirectory(named: "cli-pack-input")
        let candidate = unpacked.deletingLastPathComponent().appendingPathComponent("cli-pack-output.pak")

        XCTAssertEqual(CLI.run(arguments: ["pak", "unpack", TestFixtures.initialPak.path, unpacked.path]).exitCode, 0)
        let packResult = CLI.run(arguments: ["pak", "pack", unpacked.path, candidate.path])

        XCTAssertEqual(packResult.exitCode, 0)
        XCTAssertTrue(packResult.stdout.contains("packed 10308 entries"))
        XCTAssertEqual(CLI.run(arguments: ["pak", "verify-content-equivalent", TestFixtures.initialPak.path, candidate.path]).exitCode, 0)
        XCTAssertEqual(CLI.run(arguments: ["pak", "verify-snowpak-layout", candidate.path]).exitCode, 0)
    }

    func testCLICacheBlockUnpackPackAndVerifyRoundTrip() throws {
        let cacheBlock = try TestFixtures.extractInitialCacheBlock(from: TestFixtures.initialPak)
        let unpacked = try temporaryDirectory(named: "cli-cache-unpack")
        let rebuilt = unpacked.deletingLastPathComponent().appendingPathComponent("cli.cache_block")

        let unpackResult = CLI.run(arguments: ["cache-block", "unpack", cacheBlock.path, unpacked.path])
        XCTAssertEqual(unpackResult.exitCode, 0)
        XCTAssertTrue(unpackResult.stdout.contains("unpacked"))

        let packResult = CLI.run(arguments: ["cache-block", "pack", unpacked.path, rebuilt.path])
        XCTAssertEqual(packResult.exitCode, 0)
        XCTAssertTrue(packResult.stdout.contains("packed"))

        let verifyResult = CLI.run(arguments: ["cache-block", "verify-content-equivalent", cacheBlock.path, rebuilt.path])
        XCTAssertEqual(verifyResult.exitCode, 0)
        XCTAssertTrue(verifyResult.stdout.contains("PASS"))
    }

    func testCLILoadListInspectMatchesInspectorOutput() throws {
        let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)

        let result = CLI.run(arguments: ["load-list", "inspect", url.path])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        let manifest = try LoadListReader.readManifest(from: url)
        XCTAssertEqual(result.stdout, LoadListInspector.compactReport(manifest))
    }

    func testCLILoadListInspectWithMissingArgumentFails() {
        let result = CLI.run(arguments: ["load-list", "inspect"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool load-list inspect"))
    }

    func testCLILoadListCreateInitialWritesParseableManifest() throws {
        guard let sharedPak = TestFixtures.optionalSharedPak(),
              let sharedSoundPak = TestFixtures.optionalSharedSoundPak() else {
            throw XCTSkip("fixtures/shared.pak and fixtures/shared_sound.pak required for create-initial test")
        }
        let target = try temporaryDirectory(named: "cli-load-list")
            .appendingPathComponent("pak.load_list")

        let result = CLI.run(arguments: [
            "load-list", "create-initial",
            target.path,
            TestFixtures.initialPak.path,
            sharedPak.path,
            sharedSoundPak.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("created"))

        let manifest = try LoadListReader.readManifest(from: target)
        XCTAssertEqual(manifest.phaseOrder, LoadListConstants.phasesInWriteOrder)
    }

    func testCLILoadListCreateInitialWithWrongArgCountFails() {
        let result = CLI.run(arguments: ["load-list", "create-initial", "target", "initial.pak"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool load-list create-initial"))
    }

    func testCLIPakPackRebuildLoadListProducesVerifiableArchive() throws {
        guard let sharedPak = TestFixtures.optionalSharedPak() else {
            throw XCTSkip("fixtures/shared.pak not present")
        }
        guard let sharedSoundPak = TestFixtures.optionalSharedSoundPak() else {
            throw XCTSkip("fixtures/shared_sound.pak not present")
        }

        let mixedRoot = try temporaryDirectory(named: "cli-rebuild-root")
        let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("cli-rebuild.pak")

        XCTAssertEqual(CLI.run(arguments: ["pak", "unpack", TestFixtures.initialPak.path, mixedRoot.path]).exitCode, 0)
        XCTAssertEqual(CLI.run(arguments: [
            "cache-block", "unpack",
            mixedRoot.appendingPathComponent("initial.cache_block").path,
            mixedRoot.path
        ]).exitCode, 0)

        let result = CLI.run(arguments: [
            "pak", "pack",
            "--rebuild-load-list", "--mixed-cache-block",
            mixedRoot.path, candidate.path,
            sharedPak.path,
            sharedSoundPak.path
        ])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("packed"))
        XCTAssertEqual(CLI.run(arguments: ["pak", "verify-basic", candidate.path]).exitCode, 0)
        XCTAssertEqual(CLI.run(arguments: ["pak", "verify-snowpak-layout", candidate.path]).exitCode, 0)
    }

    func testCLIPakPackRebuildLoadListAcceptsFlagsInEitherOrder() throws {
        guard let sharedPak = TestFixtures.optionalSharedPak() else {
            throw XCTSkip("fixtures/shared.pak not present")
        }
        guard let sharedSoundPak = TestFixtures.optionalSharedSoundPak() else {
            throw XCTSkip("fixtures/shared_sound.pak not present")
        }

        let mixedRoot = try temporaryDirectory(named: "cli-rebuild-flag-order")
        let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("cli-rebuild-order.pak")

        XCTAssertEqual(CLI.run(arguments: ["pak", "unpack", TestFixtures.initialPak.path, mixedRoot.path]).exitCode, 0)
        XCTAssertEqual(CLI.run(arguments: [
            "cache-block", "unpack",
            mixedRoot.appendingPathComponent("initial.cache_block").path,
            mixedRoot.path
        ]).exitCode, 0)

        let result = CLI.run(arguments: [
            "pak", "pack",
            "--mixed-cache-block", "--rebuild-load-list",
            mixedRoot.path, candidate.path,
            sharedPak.path,
            sharedSoundPak.path
        ])

        XCTAssertEqual(result.exitCode, 0)
    }

    func testCLIPakPackRebuildLoadListRequiresFourPositionals() {
        let result = CLI.run(arguments: [
            "pak", "pack", "--rebuild-load-list", "dir", "out.pak"
        ])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool pak pack"))
    }

    func testCLIPakPackRejectsUnknownFlag() {
        let result = CLI.run(arguments: [
            "pak", "pack", "--unknown-flag", "dir", "out.pak"
        ])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool pak pack"))
    }

    func testCLIPakPackRejectsDuplicateFlag() {
        let result = CLI.run(arguments: [
            "pak", "pack", "--mixed-cache-block", "--mixed-cache-block", "dir", "out.pak"
        ])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool pak pack"))
    }

    func testCLIPackMixedCacheBlockWritesVerifiableArchive() throws {
        let mixedRoot = try temporaryDirectory(named: "cli-mixed-root")
        let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("cli-mixed.pak")

        XCTAssertEqual(CLI.run(arguments: ["pak", "unpack", TestFixtures.initialPak.path, mixedRoot.path]).exitCode, 0)
        XCTAssertEqual(CLI.run(arguments: [
            "cache-block", "unpack",
            mixedRoot.appendingPathComponent("initial.cache_block").path,
            mixedRoot.path
        ]).exitCode, 0)

        let packResult = CLI.run(arguments: ["pak", "pack", "--mixed-cache-block", mixedRoot.path, candidate.path])

        XCTAssertEqual(packResult.exitCode, 0)
        XCTAssertTrue(packResult.stdout.contains("packed"))
        XCTAssertEqual(CLI.run(arguments: ["pak", "verify-basic", candidate.path]).exitCode, 0)
        XCTAssertEqual(CLI.run(arguments: ["pak", "verify-snowpak-layout", candidate.path]).exitCode, 0)
    }

    func testWorkspaceCLIInitAddVerifyAndBuild() throws {
        let workspace = try temporaryDirectory(named: "cli-workspace")
        let mod = try makePak(named: "demo.pak", entries: [
            "classes/trucks/demo.xml": Data("<Truck/>".utf8)
        ])

        let initResult = CLI.run(arguments: ["workspace", workspace.path, "--init", TestFixtures.initialPak.path])
        XCTAssertEqual(initResult.exitCode, 0, initResult.stderr)
        XCTAssertTrue(initResult.stdout.contains("initialized workspace"))

        let addResult = CLI.run(arguments: ["workspace", workspace.path, "--add-mods", mod.path])
        XCTAssertEqual(addResult.exitCode, 0, addResult.stderr)
        XCTAssertTrue(addResult.stdout.contains("added 1 mod"))

        let verifyResult = CLI.run(arguments: ["workspace", workspace.path, "--verify"])
        XCTAssertEqual(verifyResult.exitCode, 0, verifyResult.stderr)
        XCTAssertTrue(verifyResult.stdout.contains("verified workspace"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))

        let buildResult = CLI.run(arguments: ["workspace", workspace.path, "--build"])
        XCTAssertEqual(buildResult.exitCode, 0, buildResult.stderr)
        XCTAssertTrue(buildResult.stdout.contains("built workspace"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))
    }

    func testWorkspaceCLIVerifyAndBuildReportCustomizationPresetMerges() throws {
        let base = try makeSyntheticInitialPak(
            records: [],
            customizationPresetData: customizationPresetData([
                truckXML(name: "base", marker: "base")
            ])
        )
        let workspace = try temporaryDirectory(named: "cli-workspace-customization")
        let mod = try makePak(named: "preset.pak", entries: [
            "classes/customization_presets/customization_preset.xml": customizationPresetData([
                truckXML(name: "mod", marker: "mod")
            ])
        ])

        let initResult = CLI.run(arguments: ["workspace", workspace.path, "--init", base.path])
        XCTAssertEqual(initResult.exitCode, 0, initResult.stderr)

        let addResult = CLI.run(arguments: ["workspace", workspace.path, "--add-mods", mod.path])
        XCTAssertEqual(addResult.exitCode, 0, addResult.stderr)

        let verifyResult = CLI.run(arguments: ["workspace", workspace.path, "--verify"])
        XCTAssertEqual(verifyResult.exitCode, 0, verifyResult.stderr)
        XCTAssertTrue(verifyResult.stdout.contains("customization preset merges: 1"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))

        let buildResult = CLI.run(arguments: ["workspace", workspace.path, "--build"])
        XCTAssertEqual(buildResult.exitCode, 0, buildResult.stderr)
        XCTAssertTrue(buildResult.stdout.contains("customization preset merges: 1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: PakWorkspacePaths.buildInitialPak(root: workspace).path))
    }

    func testWorkspaceCLIRejectsMissingArguments() {
        let result = CLI.run(arguments: ["workspace"])

        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.stderr.contains("Usage: snowrunner-tool workspace"))
    }
}
