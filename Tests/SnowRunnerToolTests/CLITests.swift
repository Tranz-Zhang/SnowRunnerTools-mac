import Foundation
import XCTest
@testable import SnowRunnerTool

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
}
