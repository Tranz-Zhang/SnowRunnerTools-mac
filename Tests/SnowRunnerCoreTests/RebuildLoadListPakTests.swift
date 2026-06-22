import XCTest
@testable import SnowRunnerCore

final class RebuildLoadListPakTests: XCTestCase {
    func testRebuildLoadListPakPassesExistingPakVerifiers() throws {
        guard let sharedPak = TestFixtures.optionalSharedPak() else {
            throw XCTSkip("fixtures/shared.pak not present")
        }
        guard let sharedSoundPak = TestFixtures.optionalSharedSoundPak() else {
            throw XCTSkip("fixtures/shared_sound.pak not present")
        }

        let mixedRoot = try temporaryDirectory(named: "rebuild-root")
        let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("rebuild.pak")

        try PakUnpacker.unpack(archiveURL: TestFixtures.initialPak, toDirectory: mixedRoot)
        try CacheBlockUnpacker.unpack(
            cacheBlockURL: mixedRoot.appendingPathComponent("initial.cache_block"),
            toDirectory: mixedRoot
        )

        try PakWriter.writeArchive(
            fromDirectory: mixedRoot,
            to: candidate,
            rebuildLoadList: true,
            mixedCacheBlock: true,
            sharedPak: sharedPak,
            sharedSoundPak: sharedSoundPak
        )

        let archive = try PakReader.readArchive(at: candidate)
        XCTAssertEqual(archive.entries.first?.name, "pak.load_list")
        XCTAssertTrue(try PakVerifier.verifyBasic(archive).isEmpty)
        XCTAssertTrue(try PakVerifier.verifySnowPakLayout(archive).isEmpty)

        let manifestData = try PakReader.readUncompressedPayload(entry: archive.entries[0], in: archive)
        let manifest = try LoadListReader.readManifest(data: manifestData)
        XCTAssertFalse(manifest.phaseOrder.isEmpty)
    }

    func testRebuildLoadListRequiresSharedPak() throws {
        let mixedRoot = try temporaryDirectory(named: "rebuild-missing-shared")
        let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("rebuild.pak")
        try FileManager.default.createDirectory(at: mixedRoot, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try PakWriter.writeArchive(
                fromDirectory: mixedRoot,
                to: candidate,
                rebuildLoadList: true,
                mixedCacheBlock: false,
                sharedPak: nil,
                sharedSoundPak: nil
            )
        ) { error in
            XCTAssertEqual(error as? PakWriterError, PakWriterError.missingSharedPak)
        }
    }

    func testRebuildLoadListRequiresSharedSoundPak() throws {
        guard let sharedPak = TestFixtures.optionalSharedPak() else {
            throw XCTSkip("fixtures/shared.pak not present")
        }
        let mixedRoot = try temporaryDirectory(named: "rebuild-missing-shared-sound")
        let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("rebuild.pak")

        XCTAssertThrowsError(
            try PakWriter.writeArchive(
                fromDirectory: mixedRoot,
                to: candidate,
                rebuildLoadList: true,
                mixedCacheBlock: false,
                sharedPak: sharedPak,
                sharedSoundPak: nil
            )
        ) { error in
            XCTAssertEqual(error as? PakWriterError, PakWriterError.missingSharedSoundPak)
        }
    }

    func testRebuildAddsControlledClsLoaderRecord() throws {
        guard let sharedPak = TestFixtures.optionalSharedPak() else {
            throw XCTSkip("fixtures/shared.pak not present")
        }
        guard let sharedSoundPak = TestFixtures.optionalSharedSoundPak() else {
            throw XCTSkip("fixtures/shared_sound.pak not present")
        }

        let mixedRoot = try temporaryDirectory(named: "rebuild-add-one")
        let candidate = mixedRoot.deletingLastPathComponent().appendingPathComponent("rebuild-add-one.pak")
        try PakUnpacker.unpack(archiveURL: TestFixtures.initialPak, toDirectory: mixedRoot)
        try CacheBlockUnpacker.unpack(
            cacheBlockURL: mixedRoot.appendingPathComponent("initial.cache_block"),
            toDirectory: mixedRoot
        )

        let extraFile = mixedRoot.appendingPathComponent("[media]")
            .appendingPathComponent("classes")
            .appendingPathComponent("trucks")
            .appendingPathComponent("phase4_probe.xml")
        try FileManager.default.createDirectory(
            at: extraFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("<truck phase4_probe=\"1\"/>".utf8).write(to: extraFile)

        try PakWriter.writeArchive(
            fromDirectory: mixedRoot,
            to: candidate,
            rebuildLoadList: true,
            mixedCacheBlock: true,
            sharedPak: sharedPak,
            sharedSoundPak: sharedSoundPak
        )

        let archive = try PakReader.readArchive(at: candidate)
        let manifestData = try PakReader.readUncompressedPayload(entry: archive.entries[0], in: archive)
        let manifest = try LoadListReader.readManifest(data: manifestData)
        let descBlock = manifest.recordsByPhase["CLASSES load", default: []]

        XCTAssertTrue(descBlock.contains { record in
            record.manifestPath == "<media>\\classes\\trucks\\phase4_probe.xml"
                && record.loaderType == "cls_loader"
                && record.sourcePak == "initial.pak"
        })
    }
}
