import XCTest
@testable import SnowRunnerTool

final class LoadListReaderTests: XCTestCase {
    func testReaderRecognizesReferenceManifestVersionTagAndPhaseSet() throws {
        let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
        let manifest = try LoadListReader.readManifest(from: url)

        XCTAssertEqual(manifest.versionTag, LoadListConstants.versionTag)
        XCTAssertEqual(manifest.phaseOrder, LoadListConstants.phasesInWriteOrder)
        XCTAssertEqual(manifest.recordFlags.count, 17917)
        XCTAssertEqual(manifest.headerTail, 0x00000003)
    }
}
