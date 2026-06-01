import Foundation
import XCTest
@testable import SnowRunnerTool

final class LoadListBuilderTests: XCTestCase {
    func testBuilderProducesParseableManifestFromRecordSet() throws {
        let records: [LoadListRecord] = [
            LoadListRecord(
                manifestPath: "<media>\\classes\\trucks\\hummer_h2.xml",
                loaderType: "cls_loader",
                sourcePak: "initial.pak",
                json: nil,
                phase: "CLASSES load"
            ),
            LoadListRecord(
                manifestPath: "<media>\\_templates\\trucks.xml",
                loaderType: "tpl_loader",
                sourcePak: "initial.pak",
                json: nil,
                phase: "TEMPLATES load"
            ),
            LoadListRecord(
                manifestPath: "<ssl_cache>\\initial_debug.sslbundle",
                loaderType: "sslbundle",
                sourcePak: "initial.pak",
                json: nil,
                phase: "SSL_INITIAL load"
            )
        ]

        let manifest = try LoadListBuilder.buildManifest(records: records)

        XCTAssertEqual(manifest.phaseOrder, LoadListConstants.phasesInWriteOrder)
        XCTAssertEqual(manifest.recordsByPhase["CLASSES load", default: []].count, 1)
        XCTAssertEqual(manifest.recordsByPhase["TEMPLATES load", default: []].count, 1)
        XCTAssertEqual(manifest.recordsByPhase["SSL_INITIAL load", default: []].count, 1)
        XCTAssertEqual(manifest.recordsByPhase["MESH load", default: []].count, 0)

        // Total entries = 1 Start + 13 Stages + 3 Assets + 1 End.
        XCTAssertEqual(manifest.entries.count, 1 + 13 + 3 + 1)

        // The encoded manifest must round-trip through the parser unchanged.
        let bytes = try LoadListWriter.encodeManifest(manifest)
        let parsed = try LoadListReader.readManifest(data: bytes)
        XCTAssertEqual(parsed.entries, manifest.entries)
        for phase in LoadListConstants.phasesInWriteOrder {
            XCTAssertEqual(
                parsed.recordsByPhase[phase, default: []].count,
                manifest.recordsByPhase[phase, default: []].count,
                phase
            )
        }
    }

    func testBuilderRejectsRecordWithUnknownPhase() {
        let bogus = LoadListRecord(
            manifestPath: "<media>\\bogus.xml",
            loaderType: "cls_loader",
            sourcePak: "initial.pak",
            json: nil,
            phase: "BOGUS load"
        )

        XCTAssertThrowsError(try LoadListBuilder.buildManifest(records: [bogus])) { error in
            guard case LoadListError.invalidPhaseTag = error else {
                XCTFail("expected invalidPhaseTag, got \(error)")
                return
            }
        }
    }

    func testBuilderRejectsDuplicateRecord() {
        let record = LoadListRecord(
            manifestPath: "<media>\\classes\\trucks\\hummer_h2.xml",
            loaderType: "cls_loader",
            sourcePak: "initial.pak",
            json: nil,
            phase: "CLASSES load"
        )

        XCTAssertThrowsError(try LoadListBuilder.buildManifest(records: [record, record])) { error in
            guard case LoadListError.duplicateRecord = error else {
                XCTFail("expected duplicateRecord, got \(error)")
                return
            }
        }
    }

    func testBuilderAllowsCaseVariantRecordsObservedInReferenceManifest() throws {
        let upper = LoadListRecord(
            manifestPath: "<meshes>\\landmarks_AWMG_ac1610_lmk",
            loaderType: "mesh_loader",
            sourcePak: "shared.pak",
            json: nil,
            phase: "MESH load"
        )
        let lower = LoadListRecord(
            manifestPath: "<meshes>\\landmarks_awmg_ac1610_lmk",
            loaderType: "mesh_loader",
            sourcePak: "shared.pak",
            json: nil,
            phase: "MESH load"
        )

        let manifest = try LoadListBuilder.buildManifest(records: [upper, lower])

        XCTAssertEqual(manifest.recordsByPhase["MESH load", default: []].count, 2)
    }

    func testBuilderInitialPakOnlyMatchesReferenceForInitialPakBackedPhases() throws {
        // The shared.pak/shared_sound.pak fixtures may be unavailable, but
        // initial.pak alone fully covers the SSL_INITIAL/sslbundle, TEMPLATES,
        // and CLASSES record sets. This test pins those subsets to the
        // reference manifest without depending on the optional fixtures.
        let referenceURL = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
        let reference = try LoadListReader.readManifest(from: referenceURL)

        let archive = try PakReader.readArchive(at: TestFixtures.initialPak)
        var records: [LoadListRecord] = []
        for entry in archive.entries {
            if let record = try LoadListClassifier.classify(.init(
                internalName: entry.name,
                sourcePak: "initial.pak"
            )) {
                records.append(record)
            }
        }
        let manifest = try LoadListBuilder.buildManifest(records: records)

        for phase in ["TEMPLATES load", "CLASSES load"] {
            let expected = Set((reference.recordsByPhase[phase] ?? []).map(\.manifestPath))
            let actual = Set((manifest.recordsByPhase[phase] ?? []).map(\.manifestPath))
            XCTAssertEqual(actual, expected, phase)
        }

        // SSL_INITIAL load splits across initial.pak (sslbundle) and
        // shared_debug.pak (spdb); only the sslbundle subset is sourced from
        // initial.pak.
        let referenceSSL = (reference.recordsByPhase["SSL_INITIAL load"] ?? [])
            .filter { $0.loaderType == "sslbundle" }
            .map(\.manifestPath)
        let actualSSL = (manifest.recordsByPhase["SSL_INITIAL load"] ?? [])
            .filter { $0.loaderType == "sslbundle" }
            .map(\.manifestPath)
        XCTAssertEqual(Set(actualSSL), Set(referenceSSL))
    }

    func testBuilderRuntimePaksContainReferenceManifestRecordsTheyCanSupply() throws {
        guard let sharedPak = TestFixtures.optionalSharedPak(),
              let sharedSoundPak = TestFixtures.optionalSharedSoundPak() else {
            throw XCTSkip("fixtures/shared.pak and fixtures/shared_sound.pak required for runtime-superset test")
        }

        let referenceURL = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
        let reference = try LoadListReader.readManifest(from: referenceURL)

        let manifest = try LoadListBuilder.buildManifestFromPaks(inputs: .init(
            initialPak: TestFixtures.initialPak,
            sharedPak: sharedPak,
            sharedSoundPak: sharedSoundPak
        ))

        for phase in LoadListConstants.phasesInWriteOrder {
            // Runtime shared.pak/shared_sound.pak can be a superset of the
            // original base-game fixtures. Require all records that can be
            // supplied by the available inputs, but do not fail on extra
            // runtime/DLC records or records that require missing shared_debug.pak.
            let expected = Set((reference.recordsByPhase[phase] ?? [])
                .filter { $0.sourcePak != "shared_debug.pak" }
                .map(\.manifestPath))
            let actual = Set((manifest.recordsByPhase[phase] ?? []).map(\.manifestPath))
            let missing = expected.subtracting(actual)
            XCTAssertTrue(missing.isEmpty, "\(phase) missing records: \(Array(missing.prefix(10)))")
        }
    }
}
