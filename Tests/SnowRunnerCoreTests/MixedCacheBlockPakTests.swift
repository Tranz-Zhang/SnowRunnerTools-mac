import Foundation
import XCTest
@testable import SnowRunnerCore

final class MixedCacheBlockPakTests: XCTestCase {
    func testMixedCacheBlockPakPacksGeneratedInitialCacheBlock() throws {
        let mixedRoot = try temporaryDirectory(named: "mixed-pak-root")
        let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("mixed.pak")

        try PakUnpacker.unpack(archiveURL: TestFixtures.initialPak, toDirectory: mixedRoot)
        try CacheBlockUnpacker.unpack(
            cacheBlockURL: mixedRoot.appendingPathComponent("initial.cache_block"),
            toDirectory: mixedRoot
        )

        try PakWriter.writeArchive(fromDirectory: mixedRoot, to: candidate, mixedCacheBlock: true)

        let archive = try PakReader.readArchive(at: candidate)
        XCTAssertEqual(archive.entries[0].name, "pak.load_list")
        XCTAssertEqual(archive.entries[1].name, "initial.cache_block")
        XCTAssertFalse(archive.entries.contains { $0.name.hasPrefix("[ps]\\") })
        XCTAssertFalse(archive.entries.contains { $0.name.hasPrefix("[ps_common]\\") })
        XCTAssertFalse(archive.entries.contains { $0.name.hasPrefix("[strings]\\") })

        let cacheBlockEntry = try XCTUnwrap(archive.entries.first { $0.name == "initial.cache_block" })
        let cacheBlock = try CacheBlockReader.readArchive(
            data: PakReader.readUncompressedPayload(entry: cacheBlockEntry, in: archive),
            url: nil
        )
        XCTAssertTrue(cacheBlock.entries.contains { $0.externalPath.hasPrefix("[strings]/") })
    }

    func testMixedCacheBlockPakPassesExistingPakVerifiers() throws {
        let mixedRoot = try temporaryDirectory(named: "mixed-verifier-root")
        let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("mixed-verifier.pak")

        try PakUnpacker.unpack(archiveURL: TestFixtures.initialPak, toDirectory: mixedRoot)
        try CacheBlockUnpacker.unpack(
            cacheBlockURL: mixedRoot.appendingPathComponent("initial.cache_block"),
            toDirectory: mixedRoot
        )
        try PakWriter.writeArchive(fromDirectory: mixedRoot, to: candidate, mixedCacheBlock: true)

        let archive = try PakReader.readArchive(at: candidate)
        XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
        XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)
    }
}
