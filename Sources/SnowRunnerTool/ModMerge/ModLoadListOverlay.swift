import Foundation

public struct ModLoadListOverlayResult: Equatable {
    public let manifest: LoadListManifest
    public let modManagedRecords: [LoadListRecord]
    public let netNewRecordCount: Int
    public let sourceOverrides: [ModLoadListSourceOverride]
}

public struct ModLoadListSourceOverride: Equatable {
    public let manifestPath: String
    public let previousSourcePak: String
    public let newSourcePak: String
}

public enum ModLoadListOverlay {
    public static func overlay(
        baseManifest: LoadListManifest,
        mappedEntries: [ModMappedEntry]
    ) throws -> ModLoadListOverlayResult {
        let baseRecords = flattenRecords(baseManifest)
        var recordsByPath = Dictionary(uniqueKeysWithValues: baseRecords.map { ($0.manifestPath, $0) })
        var modRecords: [LoadListRecord] = []
        var netNewRecordCount = 0
        var sourceOverrides: [ModLoadListSourceOverride] = []

        for entry in mappedEntries {
            guard let record = try LoadListClassifier.classifyMergedInitialModEntry(entry.internalName) else {
                continue
            }

            modRecords.append(record)
            if let existing = recordsByPath[record.manifestPath] {
                if existing.sourcePak != record.sourcePak {
                    sourceOverrides.append(ModLoadListSourceOverride(
                        manifestPath: record.manifestPath,
                        previousSourcePak: existing.sourcePak,
                        newSourcePak: record.sourcePak
                    ))
                }
            } else {
                netNewRecordCount += 1
            }
            recordsByPath[record.manifestPath] = record
        }

        let finalRecords = Array(recordsByPath.values)
        let manifest = try LoadListBuilder.buildManifest(records: finalRecords)
        return ModLoadListOverlayResult(
            manifest: manifest,
            modManagedRecords: modRecords,
            netNewRecordCount: netNewRecordCount,
            sourceOverrides: sourceOverrides
        )
    }

    private static func flattenRecords(_ manifest: LoadListManifest) -> [LoadListRecord] {
        manifest.phaseOrder.flatMap { manifest.recordsByPhase[$0] ?? [] }
    }
}
