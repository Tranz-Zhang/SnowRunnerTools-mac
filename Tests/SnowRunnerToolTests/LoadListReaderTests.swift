import XCTest
@testable import SnowRunnerTool

final class LoadListReaderTests: XCTestCase {
    func testReaderRecognizesReferenceManifestVersionTagAndPhaseSet() throws {
        let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
        let manifest = try LoadListReader.readManifest(from: url)

        XCTAssertEqual(manifest.versionTag, LoadListConstants.versionTag)
        XCTAssertEqual(manifest.phaseOrder, LoadListConstants.phasesInWriteOrder)
        XCTAssertEqual(manifest.entries.count, 17917)
        XCTAssertEqual(manifest.headerTail, 0x00000003)
        XCTAssertEqual(manifest.entries.first?.kind, .start)
        XCTAssertEqual(manifest.entries.last?.kind, .end)
    }

    func testReaderParsesEveryRecordInReferenceManifest() throws {
        let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
        let manifest = try LoadListReader.readManifest(from: url)

        let total = manifest.phaseOrder.reduce(0) { partial, phase in
            partial + (manifest.recordsByPhase[phase]?.count ?? 0)
        }
        XCTAssertEqual(total, 17902)

        let classes = manifest.recordsByPhase["CLASSES load", default: []]
        XCTAssertEqual(classes.count, 10284)
        XCTAssertTrue(classes.contains {
            $0.loaderType == "cls_loader"
                && $0.manifestPath.hasPrefix("<media>\\classes\\trucks")
                && $0.sourcePak == "initial.pak"
        })

        let mesh = manifest.recordsByPhase["MESH load", default: []]
        XCTAssertEqual(mesh.count, 7606)
        XCTAssertTrue(mesh.allSatisfy { $0.loaderType == "mesh_loader" && $0.sourcePak == "shared.pak" })

        let sound = manifest.recordsByPhase["SOUND load", default: []]
        XCTAssertEqual(sound.count, 1)
        XCTAssertEqual(sound.first?.loaderType, "sound_loader")
        XCTAssertEqual(sound.first?.sourcePak, "shared_sound.pak")

        let templates = manifest.recordsByPhase["TEMPLATES load", default: []]
        XCTAssertEqual(templates.count, 5)
        XCTAssertTrue(templates.allSatisfy { $0.loaderType == "tpl_loader" && $0.sourcePak == "initial.pak" })

        let sslInitial = manifest.recordsByPhase["SSL_INITIAL load", default: []]
        XCTAssertEqual(sslInitial.count, 6)
        XCTAssertEqual(sslInitial.filter { $0.loaderType == "spdb" && $0.sourcePak == "shared_debug.pak" }.count, 3)
        XCTAssertEqual(sslInitial.filter { $0.loaderType == "sslbundle" && $0.sourcePak == "initial.pak" }.count, 3)

        XCTAssertEqual(manifest.recordsByPhase["DESC_BLOCK load", default: []].count, 0)
        XCTAssertEqual(manifest.recordsByPhase["RES3_INIT load", default: []].count, 0)
        XCTAssertEqual(manifest.recordsByPhase["SSL_SOURCES_PARSE load", default: []].count, 0)
    }

    func testReaderRejectsTruncatedManifest() {
        let bytes = Data([0x01, 0x00, 0x00, 0x00])
        XCTAssertThrowsError(try LoadListReader.readManifest(data: bytes))
    }
}
