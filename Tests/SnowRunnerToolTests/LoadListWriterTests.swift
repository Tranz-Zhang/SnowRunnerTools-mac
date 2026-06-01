import XCTest
@testable import SnowRunnerTool

final class LoadListWriterTests: XCTestCase {
    func testWriterRoundTripsParsedReferenceManifestByteForByte() throws {
        let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
        let original = try Data(contentsOf: url)
        let manifest = try LoadListReader.readManifest(data: original)

        let written = try LoadListWriter.encodeManifest(manifest)

        XCTAssertEqual(written.count, original.count)
        XCTAssertEqual(written, original)
    }

    func testWriterRejectsManifestWithMissingStart() {
        let manifest = LoadListManifest(
            versionTag: LoadListConstants.versionTag,
            headerTail: 3,
            entries: [
                LoadListEntry(kind: .end, dependsOn: [], magicA: [], magicB: [1, 1], strings: []),
                LoadListEntry(kind: .end, dependsOn: [0], magicA: [], magicB: [1, 1], strings: [])
            ],
            recordsByPhase: [:],
            phaseOrder: []
        )
        XCTAssertThrowsError(try LoadListWriter.encodeManifest(manifest))
    }

    func testWriterRejectsNonASCIIString() {
        let manifest = LoadListManifest(
            versionTag: LoadListConstants.versionTag,
            headerTail: 3,
            entries: [
                LoadListEntry(kind: .start, dependsOn: [], magicA: [], magicB: [1, 1], strings: []),
                LoadListEntry(kind: .stage, dependsOn: [0], magicA: [1], magicB: [1, 1], strings: ["caf\u{00E9} load"]),
                LoadListEntry(kind: .end, dependsOn: [1], magicA: [], magicB: [1, 1], strings: [])
            ],
            recordsByPhase: [:],
            phaseOrder: ["caf\u{00E9} load"]
        )
        XCTAssertThrowsError(try LoadListWriter.encodeManifest(manifest))
    }
}
