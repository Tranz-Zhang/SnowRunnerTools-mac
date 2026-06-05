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
        mappedEntries: [ModMappedEntry],
        textureSourcePakOverride: String? = nil
    ) throws -> ModLoadListOverlayResult {
        var finalRecords = flattenRecords(baseManifest)
        var modRecords: [LoadListRecord] = []
        var netNewRecordCount = 0
        var sourceOverrides: [ModLoadListSourceOverride] = []

        for entry in mappedEntries {
            let textureSourcePak = textureSourcePakOverride ?? "shared_textures.pak"
            let records = try LoadListClassifier.classifyMergedModEntry(
                entry.internalName,
                textureSourcePak: textureSourcePak
            )
            for record in records {
                modRecords.append(record)

                if let exactIndex = finalRecords.firstIndex(where: { recordIdentity($0) == recordIdentity(record) }) {
                    finalRecords[exactIndex] = record
                    continue
                }

                if textureSourcePakOverride != nil,
                   isPCTTextureRecord(record),
                   let textureIndex = finalRecords.firstIndex(where: {
                       $0.manifestPath == record.manifestPath && $0.loaderType == record.loaderType
                   }) {
                    let existing = finalRecords[textureIndex]
                    if existing.sourcePak != record.sourcePak {
                        sourceOverrides.append(ModLoadListSourceOverride(
                            manifestPath: record.manifestPath,
                            previousSourcePak: existing.sourcePak,
                            newSourcePak: record.sourcePak
                        ))
                    }
                    finalRecords[textureIndex] = record
                    continue
                }

                if shouldReplaceByManifestPath(record),
                   let pathIndex = finalRecords.firstIndex(where: { $0.manifestPath == record.manifestPath }) {
                    let existing = finalRecords[pathIndex]
                    if existing.sourcePak != record.sourcePak {
                        sourceOverrides.append(ModLoadListSourceOverride(
                            manifestPath: record.manifestPath,
                            previousSourcePak: existing.sourcePak,
                            newSourcePak: record.sourcePak
                        ))
                    }
                    finalRecords[pathIndex] = record
                } else {
                    netNewRecordCount += 1
                    finalRecords.append(record)
                }
            }
        }

        let manifest = try LoadListBuilder.buildManifest(records: finalRecords)
        return ModLoadListOverlayResult(
            manifest: manifest,
            modManagedRecords: modRecords,
            netNewRecordCount: netNewRecordCount,
            sourceOverrides: sourceOverrides
        )
    }

    private static func shouldReplaceByManifestPath(_ record: LoadListRecord) -> Bool {
        !(record.manifestPath.hasPrefix("<textures>\\pct\\") && record.manifestPath.hasSuffix(".pct_header"))
    }

    private static func isPCTTextureRecord(_ record: LoadListRecord) -> Bool {
        record.manifestPath.hasPrefix("<textures>\\pct\\")
            && record.manifestPath.hasSuffix(".pct_header")
            && (record.loaderType == "pct_mr2_header" || record.loaderType == "pct_faces")
    }

    private static func recordIdentity(_ record: LoadListRecord) -> String {
        [
            record.phase,
            record.manifestPath,
            record.loaderType,
            record.sourcePak,
            record.json ?? ""
        ].joined(separator: "\u{1F}")
    }

    private static func flattenRecords(_ manifest: LoadListManifest) -> [LoadListRecord] {
        manifest.phaseOrder.flatMap { manifest.recordsByPhase[$0] ?? [] }
    }
}
