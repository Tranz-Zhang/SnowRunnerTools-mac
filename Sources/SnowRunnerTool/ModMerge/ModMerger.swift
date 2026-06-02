import Foundation

public enum ModMerger {
    public static func merge(
        baseInitialPak: URL,
        outputInitialPak: URL,
        modPaks: [URL],
        options: ModMergeOptions
    ) throws -> ModMergeResult {
        try validateOutputPath(outputInitialPak, inputs: [baseInitialPak] + modPaks)

        let baseArchive = try PakReader.readArchive(at: baseInitialPak)
        let baseIssues = try PakVerifier.verifyBasic(baseArchive)
        if !baseIssues.isEmpty {
            throw ModMergeError.verificationFailed(name: "base verify-basic", issues: baseIssues)
        }
        let baseManifest = try readBaseManifest(from: baseArchive)

        let rawMappedEntries = try modPaks.flatMap { try ModArchiveMapper.mapArchive(at: $0) }
        let duplicateResolution = try resolveMappedDuplicates(rawMappedEntries)
        let mappedEntries = duplicateResolution.entries

        let baseNames = Set(baseArchive.entries.map(\.name))
        let collisions = mappedEntries
            .map(\.internalName)
            .filter { baseNames.contains($0) }
            .sorted()
        if !collisions.isEmpty && !options.allowOverwrite {
            throw ModMergeError.overwriteRequired(paths: collisions)
        }

        let overlay = try ModLoadListOverlay.overlay(baseManifest: baseManifest, mappedEntries: mappedEntries)
        let loadListData = try LoadListWriter.encodeManifest(overlay.manifest)
        let plan = ModMergePlan(
            baseEntryCount: baseArchive.entries.count,
            mappedModEntryCount: rawMappedEntries.count,
            netNewOuterPakEntryCount: mappedEntries.count - collisions.count,
            collisions: collisions,
            duplicateIdenticalMappedNames: duplicateResolution.duplicateIdenticalNames,
            loadListSourceOverrides: overlay.sourceOverrides,
            loadListCandidateRecords: overlay.modManagedRecords,
            netNewLoadListRecordCount: overlay.netNewRecordCount
        )

        if options.dryRun {
            let result = ModMergeResult(plan: plan, outputURL: nil, writtenEntryCount: nil)
            try writeReportIfNeeded(result, to: options.reportURL)
            return result
        }

        let sources = try buildMergedSources(
            baseArchive: baseArchive,
            mappedEntries: mappedEntries,
            loadListData: loadListData
        )
        let written = try PakWriter.writeArchive(fileSources: sources, to: outputInitialPak)
        let writtenArchive = try PakReader.readArchive(at: outputInitialPak)
        let basicIssues = try PakVerifier.verifyBasic(writtenArchive)
        if !basicIssues.isEmpty {
            throw ModMergeError.verificationFailed(name: "verify-basic", issues: basicIssues)
        }
        let layoutIssues = try PakVerifier.verifySnowPakLayout(writtenArchive)
        if !layoutIssues.isEmpty {
            throw ModMergeError.verificationFailed(name: "verify-snowpak-layout", issues: layoutIssues)
        }

        let result = ModMergeResult(plan: plan, outputURL: outputInitialPak, writtenEntryCount: written)
        try writeReportIfNeeded(result, to: options.reportURL)
        return result
    }

    private static func validateOutputPath(_ output: URL, inputs: [URL]) throws {
        let outputPath = output.standardizedFileURL.path
        for input in inputs where input.standardizedFileURL.path == outputPath {
            throw ModMergeError.outputPathMatchesInput(outputPath)
        }
    }

    private static func readBaseManifest(from archive: PakArchive) throws -> LoadListManifest {
        guard let entry = archive.entries.first(where: { $0.name == LoadListConstants.manifestEntryName }) else {
            throw ModMergeError.missingBaseManifest
        }
        let data = try PakReader.readUncompressedPayload(entry: entry, in: archive)
        return try LoadListReader.readManifest(data: data)
    }

    private static func resolveMappedDuplicates(
        _ entries: [ModMappedEntry]
    ) throws -> (entries: [ModMappedEntry], duplicateIdenticalNames: [String]) {
        var byName: [String: ModMappedEntry] = [:]
        var duplicateNames: Set<String> = []

        for entry in entries {
            if let existing = byName[entry.internalName] {
                guard existing.data == entry.data else {
                    throw ModMergeError.conflictingMappedDuplicate(path: entry.internalName)
                }
                duplicateNames.insert(entry.internalName)
            } else {
                byName[entry.internalName] = entry
            }
        }

        return (
            entries: byName.values.sorted { $0.internalName < $1.internalName },
            duplicateIdenticalNames: duplicateNames.sorted()
        )
    }

    private static func buildMergedSources(
        baseArchive: PakArchive,
        mappedEntries: [ModMappedEntry],
        loadListData: Data
    ) throws -> [PakFileSource] {
        let mappedByName = Dictionary(uniqueKeysWithValues: mappedEntries.map { ($0.internalName, $0) })
        var sources: [PakFileSource] = []
        sources.reserveCapacity(baseArchive.entries.count + mappedEntries.count)

        for entry in baseArchive.entries {
            if entry.name == LoadListConstants.manifestEntryName {
                sources.append(PakFileSource(internalName: entry.name, data: loadListData))
                continue
            }
            if let mapped = mappedByName[entry.name] {
                sources.append(PakFileSource(internalName: entry.name, data: mapped.data))
                continue
            }
            let payload = try PakReader.readUncompressedPayload(entry: entry, in: baseArchive)
            sources.append(PakFileSource(internalName: entry.name, data: payload))
        }

        let baseNames = Set(baseArchive.entries.map(\.name))
        for mapped in mappedEntries where !baseNames.contains(mapped.internalName) {
            sources.append(PakFileSource(internalName: mapped.internalName, data: mapped.data))
        }

        return try PakDirectoryScanner.sortedPackSources(sources)
    }

    private static func writeReportIfNeeded(_ result: ModMergeResult, to url: URL?) throws {
        guard let url else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try ModMergeReporter.markdown(result: result).write(to: url, atomically: true, encoding: .utf8)
    }
}
