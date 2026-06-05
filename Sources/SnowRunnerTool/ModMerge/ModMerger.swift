import Foundation

public enum ModMerger {
    public static func merge(
        baseInitialPak: URL,
        outputInitialPak: URL,
        baseSharedTexturesPak: URL? = nil,
        outputSharedTexturesPak: URL? = nil,
        modPaks: [URL],
        options: ModMergeOptions
    ) throws -> ModMergeResult {
        try validateOutputPaths(
            [outputInitialPak, outputSharedTexturesPak].compactMap { $0 },
            inputs: [baseInitialPak, baseSharedTexturesPak].compactMap { $0 } + modPaks
        )

        let baseArchive = try PakReader.readArchive(at: baseInitialPak)
        let baseIssues = try PakVerifier.verifyBasic(baseArchive)
        if !baseIssues.isEmpty {
            throw ModMergeError.verificationFailed(name: "base verify-basic", issues: baseIssues)
        }
        let baseManifest = try readBaseManifest(from: baseArchive)

        let rawMappedEntries = try modPaks.flatMap { try ModArchiveMapper.mapArchive(at: $0) }
        let duplicateResolution = try resolveMappedDuplicates(rawMappedEntries)
        let mappedEntries = duplicateResolution.entries
        let initialEntries = mappedEntries.filter { $0.targetArchive == .initial }
        let textureEntries = mappedEntries.filter { $0.targetArchive == .sharedTextures }
        let textureArchive: PakArchive?
        if textureEntries.isEmpty {
            textureArchive = nil
        } else {
            guard let baseSharedTexturesPak, outputSharedTexturesPak != nil else {
                throw ModMergeError.missingTextureOutput
            }
            textureArchive = try PakReader.readArchive(at: baseSharedTexturesPak)
        }

        let baseNames = Set(baseArchive.entries.map(\.name))
        let collisions = initialEntries
            .map(\.internalName)
            .filter { baseNames.contains($0) }
            .sorted()
        let textureBaseNames = Set((textureArchive?.entries ?? []).map(\.name))
        let textureCollisions = textureEntries
            .map(\.internalName)
            .filter { textureBaseNames.contains($0) }
            .sorted()
        let blockedCollisions = collisions + textureCollisions
        if !blockedCollisions.isEmpty && !options.allowOverwrite {
            throw ModMergeError.overwriteRequired(paths: blockedCollisions)
        }

        let overlay = try ModLoadListOverlay.overlay(baseManifest: baseManifest, mappedEntries: mappedEntries)
        let loadListData = try LoadListWriter.encodeManifest(overlay.manifest)
        let plan = ModMergePlan(
            baseEntryCount: baseArchive.entries.count,
            mappedModEntryCount: rawMappedEntries.count,
            netNewOuterPakEntryCount: initialEntries.count - collisions.count,
            collisions: collisions,
            textureBaseEntryCount: textureArchive?.entries.count ?? 0,
            netNewTexturePakEntryCount: textureEntries.count - textureCollisions.count,
            textureCollisions: textureCollisions,
            duplicateIdenticalMappedNames: duplicateResolution.duplicateIdenticalNames,
            loadListSourceOverrides: overlay.sourceOverrides,
            loadListCandidateRecords: overlay.modManagedRecords,
            netNewLoadListRecordCount: overlay.netNewRecordCount
        )

        if options.dryRun {
            let result = ModMergeResult(
                plan: plan,
                outputURL: nil,
                outputTexturesURL: nil,
                writtenEntryCount: nil,
                writtenTextureEntryCount: nil
            )
            try writeReportIfNeeded(result, to: options.reportURL)
            return result
        }

        let sources = try buildMergedSources(
            baseArchive: baseArchive,
            mappedEntries: initialEntries,
            loadListData: loadListData,
            requirePakLoadList: true
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

        let writtenTexture: Int?
        if !textureEntries.isEmpty {
            guard let textureArchive, let outputSharedTexturesPak else {
                throw ModMergeError.missingTextureOutput
            }
            let textureSources = try buildMergedSources(
                baseArchive: textureArchive,
                mappedEntries: textureEntries,
                loadListData: nil,
                requirePakLoadList: false
            )
            writtenTexture = try PakWriter.writeArchive(fileSources: textureSources, to: outputSharedTexturesPak)
            let writtenTextureArchive = try PakReader.readArchive(at: outputSharedTexturesPak)
            try PakReader.validatePayloadCRCs(in: writtenTextureArchive)
        } else {
            writtenTexture = nil
        }

        let result = ModMergeResult(
            plan: plan,
            outputURL: outputInitialPak,
            outputTexturesURL: textureEntries.isEmpty ? nil : outputSharedTexturesPak,
            writtenEntryCount: written,
            writtenTextureEntryCount: writtenTexture
        )
        try writeReportIfNeeded(result, to: options.reportURL)
        return result
    }

    private static func validateOutputPaths(_ outputs: [URL], inputs: [URL]) throws {
        var seenOutputs: Set<String> = []
        for output in outputs {
            let outputPath = output.standardizedFileURL.path
            if !seenOutputs.insert(outputPath).inserted {
                throw ModMergeError.outputPathMatchesInput(outputPath)
            }
            for input in inputs where input.standardizedFileURL.path == outputPath {
                throw ModMergeError.outputPathMatchesInput(outputPath)
            }
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
            let key = "\(entry.targetArchive.rawValue):\(entry.internalName)"
            if let existing = byName[key] {
                guard existing.data == entry.data else {
                    throw ModMergeError.conflictingMappedDuplicate(path: entry.internalName)
                }
                duplicateNames.insert(key)
            } else {
                byName[key] = entry
            }
        }

        return (
            entries: byName.values.sorted {
                if $0.targetArchive.rawValue != $1.targetArchive.rawValue {
                    return $0.targetArchive.rawValue < $1.targetArchive.rawValue
                }
                return $0.internalName < $1.internalName
            },
            duplicateIdenticalNames: duplicateNames.sorted()
        )
    }

    private static func buildMergedSources(
        baseArchive: PakArchive,
        mappedEntries: [ModMappedEntry],
        loadListData: Data?,
        requirePakLoadList: Bool
    ) throws -> [PakFileSource] {
        let mappedByName = Dictionary(uniqueKeysWithValues: mappedEntries.map { ($0.internalName, $0) })
        var sources: [PakFileSource] = []
        sources.reserveCapacity(baseArchive.entries.count + mappedEntries.count)

        for entry in baseArchive.entries {
            if entry.name == LoadListConstants.manifestEntryName, let loadListData {
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

        return try PakDirectoryScanner.sortedPackSources(sources, requirePakLoadList: requirePakLoadList)
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
