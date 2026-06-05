import Foundation

public struct LoadListBuilderInputs: Equatable {
    public let initialPak: URL
    public let sharedPak: URL
    public let sharedSoundPak: URL

    public init(initialPak: URL, sharedPak: URL, sharedSoundPak: URL) {
        self.initialPak = initialPak
        self.sharedPak = sharedPak
        self.sharedSoundPak = sharedSoundPak
    }
}

public enum LoadListBuilder {
    /// Walk the three fixture PAKs, classify each entry against the reference
    /// manifest's loader-type/phase rules, and produce a deterministic
    /// `LoadListManifest` whose record set matches the reference manifest.
    public static func buildManifestFromPaks(inputs: LoadListBuilderInputs) throws -> LoadListManifest {
        var records: [LoadListRecord] = []
        try collectRecords(from: inputs.initialPak, sourcePak: "initial.pak", into: &records)
        try collectRecords(from: inputs.sharedPak, sourcePak: "shared.pak", into: &records)
        try collectRecords(from: inputs.sharedSoundPak, sourcePak: "shared_sound.pak", into: &records)
        return try buildManifest(records: records)
    }

    /// Construct a `LoadListManifest` from an unordered set of pre-classified
    /// records. Each phase keeps a deterministic order (case-insensitive
    /// ordinal by `manifestPath`, with the raw path as tiebreaker). All 13
    /// phases are emitted whether or not they contain records.
    public static func buildManifest(records: [LoadListRecord]) throws -> LoadListManifest {
        var byPhase: [String: [LoadListRecord]] = [:]
        for record in records {
            guard LoadListConstants.phasesInWriteOrder.contains(record.phase) else {
                throw LoadListError.invalidPhaseTag(record.phase)
            }
            byPhase[record.phase, default: []].append(record)
        }

        for phase in byPhase.keys {
            let sorted = byPhase[phase]!.sorted { lhs, rhs in
                let l = lhs.manifestPath.lowercased()
                let r = rhs.manifestPath.lowercased()
                if l != r { return l < r }
                let lhsRank = loaderSortRank(lhs.loaderType)
                let rhsRank = loaderSortRank(rhs.loaderType)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.loaderType != rhs.loaderType { return lhs.loaderType < rhs.loaderType }
                if lhs.sourcePak != rhs.sourcePak { return lhs.sourcePak < rhs.sourcePak }
                if (lhs.json ?? "") != (rhs.json ?? "") { return (lhs.json ?? "") < (rhs.json ?? "") }
                return lhs.manifestPath < rhs.manifestPath
            }
            try assertNoDuplicates(in: sorted, phase: phase)
            byPhase[phase] = sorted
        }

        let entries = makeEntries(byPhase: byPhase)

        return LoadListManifest(
            versionTag: LoadListConstants.versionTag,
            headerTail: LoadListConstants.headerTail,
            entries: entries,
            recordsByPhase: byPhase,
            phaseOrder: LoadListConstants.phasesInWriteOrder
        )
    }

    // MARK: - Implementation

    private static func collectRecords(
        from pakURL: URL,
        sourcePak: String,
        into records: inout [LoadListRecord]
    ) throws {
        let archive = try PakReader.readArchive(at: pakURL)
        for entry in archive.entries {
            if let record = try LoadListClassifier.classify(.init(
                internalName: entry.name,
                sourcePak: sourcePak
            )) {
                records.append(record)
            }
        }
    }

    private static func assertNoDuplicates(
        in records: [LoadListRecord],
        phase: String
    ) throws {
        var seenExact: Set<String> = []
        for record in records {
            let key = recordIdentity(record)
            if !seenExact.insert(key).inserted {
                throw LoadListError.duplicateRecord(phase: phase, path: record.manifestPath)
            }
        }
    }

    private static func makeEntries(
        byPhase: [String: [LoadListRecord]]
    ) -> [LoadListEntry] {
        var entries: [LoadListEntry] = []
        let phaseOrder = LoadListConstants.phasesInWriteOrder

        // Compute total count to allocate dependency arrays sized correctly.
        var totalAssets = 0
        for phase in phaseOrder {
            totalAssets += (byPhase[phase]?.count ?? 0)
        }
        let totalEntries = 1 /* Start */ + phaseOrder.count /* Stages */ + totalAssets + 1 /* End */
        entries.reserveCapacity(totalEntries)

        // Start entry (idx 0).
        entries.append(LoadListEntry(
            kind: .start,
            dependsOn: [],
            magicA: [],
            magicB: [0x01, 0x01],
            strings: []
        ))

        // For each phase: emit assets first, then the closing Stage entry.
        // Per the reference manifest:
        //   Asset.dependsOn   = [previousStageOrStartIndex]
        //   Stage.dependsOn   = [head ..< stageIndex] when group has assets,
        //                       else [stageIndex - 1]
        //   End.dependsOn     = [endIndex - 1]
        var anchorIndex: Int = 0  // Start is the initial anchor.
        for phase in phaseOrder {
            let groupHead = entries.count   // first asset index for this phase
            let assets = byPhase[phase] ?? []
            var pctHeaderEntryIndexByPath: [String: Int] = [:]
            for record in assets {
                var strings = [record.manifestPath, record.loaderType, record.sourcePak]
                if let json = record.json {
                    strings.append(json)
                }
                let dependsOn: [Int32]
                if isPCTFacesLoader(record.loaderType),
                   let headerEntryIndex = pctHeaderEntryIndexByPath[record.manifestPath] {
                    dependsOn = [Int32(headerEntryIndex)]
                } else {
                    dependsOn = [Int32(anchorIndex)]
                }
                entries.append(LoadListEntry(
                    kind: .asset,
                    dependsOn: dependsOn,
                    magicA: Array(repeating: 0x01, count: strings.count),
                    magicB: [0x01, 0x01],
                    strings: strings
                ))
                if record.loaderType == "pct_mr2_header" {
                    pctHeaderEntryIndexByPath[record.manifestPath] = entries.count - 1
                }
            }
            let stageIndex = entries.count
            let groupSize = stageIndex - groupHead
            let stageDependsOn: [Int32]
            if groupSize >= 1 {
                stageDependsOn = (groupHead..<stageIndex).map { Int32($0) }
            } else {
                stageDependsOn = [Int32(stageIndex - 1)]
            }
            entries.append(LoadListEntry(
                kind: .stage,
                dependsOn: stageDependsOn,
                magicA: [0x01],
                magicB: [0x01, 0x01],
                strings: [phase]
            ))
            anchorIndex = stageIndex
        }

        // End entry depends on the previous (last Stage) index.
        let endPredecessor = Int32(entries.count - 1)
        entries.append(LoadListEntry(
            kind: .end,
            dependsOn: [endPredecessor],
            magicA: [],
            magicB: [0x01, 0x01],
            strings: []
        ))

        return entries
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

    private static func loaderSortRank(_ loader: String) -> Int {
        switch loader {
        case "pct_mr2_header":
            return 0
        case "pct_faces", "pct_inplace_faces":
            return 1
        default:
            return 2
        }
    }

    private static func isPCTFacesLoader(_ loader: String) -> Bool {
        loader == "pct_faces" || loader == "pct_inplace_faces"
    }
}
