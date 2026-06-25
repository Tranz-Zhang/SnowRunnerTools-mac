import Foundation

public enum ModMerger {
    public static func merge(
        baseInitialPak: URL,
        outputInitialPak: URL,
        baseSharedTexturesPak: URL? = nil,
        outputSharedTexturesPak: URL? = nil,
        baseHighSharedTexturesPak: URL? = nil,
        outputHighSharedTexturesPak: URL? = nil,
        modPaks: [URL],
        options: ModMergeOptions
    ) throws -> ModMergeResult {
        let experimentalModTexturesOutputURL = options.experimentalModTexturesOutputURL
        let experimentalInlineTextures = options.experimentalInlineTextures
        try validateOutputPaths(
            [outputInitialPak, outputSharedTexturesPak, outputHighSharedTexturesPak, experimentalModTexturesOutputURL]
                .compactMap { $0 },
            inputs: [baseInitialPak, baseSharedTexturesPak, baseHighSharedTexturesPak].compactMap { $0 } + modPaks
        )

        let baseArchive = try PakReader.readArchive(at: baseInitialPak)
        let baseIssues = try PakVerifier.verifyBasic(baseArchive)
        if !baseIssues.isEmpty {
            throw ModMergeError.verificationFailed(name: "base verify-basic", issues: baseIssues)
        }
        let baseManifest = try readBaseManifest(from: baseArchive)

        let rawMappedEntries = try modPaks.flatMap { try ModArchiveMapper.mapArchive(at: $0) }
        let partitionedEntries = try partitionSemanticMergeEntries(rawMappedEntries)
        let duplicateResolution = try resolveMappedDuplicates(partitionedEntries.regularEntries)
        let mappedEntries = duplicateResolution.entries
        let initialEntries = mappedEntries.filter { $0.targetArchive == .initial }
        let stringMergeEntries = partitionedEntries.stringMergeEntries
        let customizationPresetMergeEntries = partitionedEntries.customizationPresetMergeEntries
        let registryMergeEntries = partitionedEntries.registryMergeEntries
        let textureEntries = mappedEntries.filter { $0.targetArchive == .sharedTexturesBase }
        let sharedTextureEntries = mappedEntries.filter { $0.targetArchive == .sharedTextures }
        let experimentalTextureEntries = try combinedExperimentalTextureEntries(
            textureEntries + sharedTextureEntries
        )
        let textureArchive: PakArchive?
        if textureEntries.isEmpty || experimentalModTexturesOutputURL != nil || experimentalInlineTextures {
            textureArchive = nil
        } else {
            guard let baseSharedTexturesPak, outputSharedTexturesPak != nil else {
                throw ModMergeError.missingTextureOutput
            }
            textureArchive = try PakReader.readArchive(at: baseSharedTexturesPak)
        }
        let sharedTextureIndex: LargePakIndex?
        if sharedTextureEntries.isEmpty || experimentalModTexturesOutputURL != nil || experimentalInlineTextures {
            sharedTextureIndex = nil
        } else {
            guard let baseHighSharedTexturesPak, outputHighSharedTexturesPak != nil else {
                throw ModMergeError.missingSharedTextureOutput
            }
            sharedTextureIndex = try LargePakPatcher.readIndex(input: baseHighSharedTexturesPak)
        }

        let baseNames = Set(baseArchive.entries.map(\.name))
        let inlineTextureEntries = experimentalInlineTextures ? experimentalTextureEntries : []
        let collisions = initialEntries
            .map(\.internalName)
            .filter { baseNames.contains($0) }
            .sorted()
        let inlineTextureCollisions = inlineTextureEntries
            .map(\.internalName)
            .filter { baseNames.contains($0) }
            .sorted()
        let textureBaseNames = Set((textureArchive?.entries ?? []).map(\.name))
        let textureCollisions = textureEntries
            .map(\.internalName)
            .filter { textureBaseNames.contains($0) }
            .sorted()
        let sharedTextureBaseNames = Set(sharedTextureIndex?.entryNames ?? [])
        let sharedTextureCollisions = sharedTextureEntries
            .map(\.internalName)
            .filter { sharedTextureBaseNames.contains($0) }
            .sorted()
        let blockedCollisions = collisions + inlineTextureCollisions + textureCollisions + sharedTextureCollisions
        if !blockedCollisions.isEmpty && !options.allowOverwrite {
            throw ModMergeError.overwriteRequired(paths: blockedCollisions)
        }

        let textureSourcePakOverride: String?
        if experimentalInlineTextures {
            textureSourcePakOverride = "initial.pak"
        } else {
            textureSourcePakOverride = experimentalModTexturesOutputURL?.lastPathComponent
        }
        let overlayMappedEntries = mappedEntries + customizationPresetMergeEntries + registryMergeEntries
        let overlay = try ModLoadListOverlay.overlay(
            baseManifest: baseManifest,
            mappedEntries: overlayMappedEntries,
            textureSourcePakOverride: textureSourcePakOverride
        )
        let loadListData = try LoadListWriter.encodeManifest(overlay.manifest)
        let plan = ModMergePlan(
            baseEntryCount: baseArchive.entries.count,
            mappedModEntryCount: rawMappedEntries.count,
            netNewOuterPakEntryCount: initialEntries.filter { !baseNames.contains($0.internalName) }.count
                + inlineTextureEntries.filter { !baseNames.contains($0.internalName) }.count
                + stringMergeEntries.filter { !baseNames.contains($0.internalName) }.count
                + customizationPresetMergeEntries.filter { !baseNames.contains($0.internalName) }.count
                + registryMergeEntries.filter { !baseNames.contains($0.internalName) }.count,
            collisions: collisions,
            textureBaseEntryCount: textureArchive?.entries.count ?? 0,
            netNewTexturePakEntryCount: textureEntries.count - textureCollisions.count,
            textureCollisions: textureCollisions,
            sharedTextureEntryCount: sharedTextureIndex?.entryCount ?? 0,
            netNewSharedTexturePakEntryCount: sharedTextureEntries.count - sharedTextureCollisions.count,
            sharedTextureCollisions: sharedTextureCollisions,
            stringMergeEntryCount: stringMergeEntries.count,
            customizationPresetMergeEntryCount: customizationPresetMergeEntries.count,
            duplicateIdenticalMappedNames: duplicateResolution.duplicateIdenticalNames,
            loadListSourceOverrides: overlay.sourceOverrides,
            loadListCandidateRecords: overlay.modManagedRecords,
            netNewLoadListRecordCount: overlay.netNewRecordCount,
            texturesInInitial: experimentalInlineTextures
        )

        let sources = try buildMergedSources(
            baseArchive: baseArchive,
            mappedEntries: initialEntries + inlineTextureEntries,
            stringMergeEntries: stringMergeEntries,
            customizationPresetMergeEntries: customizationPresetMergeEntries,
            registryMergeEntries: registryMergeEntries,
            loadListData: loadListData,
            requirePakLoadList: true
        )
        if shouldValidateMergedReferences(changedEntries: initialEntries + registryMergeEntries) {
            try ModReferenceValidator.validateInitialSources(
                sources,
                validateClassLocalReferences: false
            )
        }

        if options.dryRun {
            let result = ModMergeResult(
                plan: plan,
                outputURL: nil,
                outputTexturesURL: nil,
                outputSharedTexturesURL: nil,
                writtenEntryCount: nil,
                writtenTextureEntryCount: nil,
                writtenSharedTextureEntryCount: nil
            )
            try writeReportIfNeeded(result, to: options.reportURL)
            return result
        }

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
        if experimentalModTexturesOutputURL != nil || experimentalInlineTextures {
            writtenTexture = nil
        } else if !textureEntries.isEmpty {
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

        let writtenSharedTexture: Int?
        if experimentalInlineTextures {
            writtenSharedTexture = nil
        } else if let experimentalModTexturesOutputURL, !experimentalTextureEntries.isEmpty {
            let textureSources = try PakDirectoryScanner.sortedPackSources(
                experimentalTextureEntries.map {
                    pakFileSource(for: $0)
                },
                requirePakLoadList: false
            )
            writtenSharedTexture = try PakWriter.writeArchive(
                fileSources: textureSources,
                to: experimentalModTexturesOutputURL
            )
            let writtenTextureArchive = try PakReader.readArchive(at: experimentalModTexturesOutputURL)
            try PakReader.validatePayloadCRCs(in: writtenTextureArchive)
        } else if !sharedTextureEntries.isEmpty {
            guard let baseHighSharedTexturesPak, let outputHighSharedTexturesPak else {
                throw ModMergeError.missingSharedTextureOutput
            }
            let additions = sharedTextureEntries.map {
                LargePakPatchEntry(
                    name: $0.internalName,
                    data: $0.data,
                    centralExtraField: $0.centralExtraField,
                    compressedPayload: $0.compressedPayload
                )
            }
            writtenSharedTexture = try LargePakPatcher.patchArchive(
                input: baseHighSharedTexturesPak,
                output: outputHighSharedTexturesPak,
                additions: additions,
                allowOverwrite: options.allowOverwrite
            )
            _ = try LargePakPatcher.readIndex(input: outputHighSharedTexturesPak)
        } else {
            writtenSharedTexture = nil
        }

        let result = ModMergeResult(
            plan: plan,
            outputURL: outputInitialPak,
            outputTexturesURL: experimentalModTexturesOutputURL == nil && !textureEntries.isEmpty
                && !experimentalInlineTextures
                ? outputSharedTexturesPak
                : nil,
            outputSharedTexturesURL: experimentalModTexturesOutputURL != nil
                && !experimentalInlineTextures
                && !experimentalTextureEntries.isEmpty
                ? experimentalModTexturesOutputURL
                : (experimentalInlineTextures ? nil : (sharedTextureEntries.isEmpty ? nil : outputHighSharedTexturesPak)),
            writtenEntryCount: written,
            writtenTextureEntryCount: writtenTexture,
            writtenSharedTextureEntryCount: writtenSharedTexture
        )
        try writeReportIfNeeded(result, to: options.reportURL)
        return result
    }

    public static func mergeWorkspaceInitial(
        initialDirectory: URL,
        baseManifest: LoadListManifest,
        mappedEntries rawMappedEntries: [ModMappedEntry],
        outputInitialPak: URL,
        reportURL: URL?,
        verifyOutput: Bool
    ) throws -> ModMergeResult {
        let initialSources = try PakDirectoryScanner.scan(rootDirectory: initialDirectory)
        let baseNames = Set(initialSources.map(\.internalName))
        let partitionedEntries = try partitionSemanticMergeEntries(rawMappedEntries)
        let duplicateResolution = try resolveMappedDuplicates(partitionedEntries.regularEntries)
        let mappedEntries = duplicateResolution.entries
        let initialEntries = mappedEntries.filter { $0.targetArchive == .initial }
        let inlineTextureEntries = try combinedExperimentalTextureEntries(
            mappedEntries.filter { $0.targetArchive == .sharedTexturesBase || $0.targetArchive == .sharedTextures }
        )
        let collisions = initialEntries
            .map(\.internalName)
            .filter { baseNames.contains($0) }
            .sorted()
        let inlineTextureCollisions = inlineTextureEntries
            .map(\.internalName)
            .filter { baseNames.contains($0) }
            .sorted()
        let stringMergeEntries = partitionedEntries.stringMergeEntries
        let customizationPresetMergeEntries = partitionedEntries.customizationPresetMergeEntries
        let registryMergeEntries = partitionedEntries.registryMergeEntries
        let overlayMappedEntries = mappedEntries + customizationPresetMergeEntries + registryMergeEntries
        let overlay = try ModLoadListOverlay.overlay(
            baseManifest: baseManifest,
            mappedEntries: overlayMappedEntries,
            textureSourcePakOverride: "initial.pak"
        )
        let loadListData = try LoadListWriter.encodeManifest(overlay.manifest)
        let plan = ModMergePlan(
            baseEntryCount: initialSources.count,
            mappedModEntryCount: rawMappedEntries.count,
            netNewOuterPakEntryCount: initialEntries.filter { !baseNames.contains($0.internalName) }.count
                + inlineTextureEntries.filter { !baseNames.contains($0.internalName) }.count
                + stringMergeEntries.filter { !baseNames.contains($0.internalName) }.count
                + customizationPresetMergeEntries.filter { !baseNames.contains($0.internalName) }.count
                + registryMergeEntries.filter { !baseNames.contains($0.internalName) }.count,
            collisions: collisions,
            textureBaseEntryCount: 0,
            netNewTexturePakEntryCount: 0,
            textureCollisions: [],
            sharedTextureEntryCount: 0,
            netNewSharedTexturePakEntryCount: inlineTextureEntries.count - inlineTextureCollisions.count,
            sharedTextureCollisions: inlineTextureCollisions,
            stringMergeEntryCount: stringMergeEntries.count,
            customizationPresetMergeEntryCount: customizationPresetMergeEntries.count,
            duplicateIdenticalMappedNames: duplicateResolution.duplicateIdenticalNames,
            loadListSourceOverrides: overlay.sourceOverrides,
            loadListCandidateRecords: overlay.modManagedRecords,
            netNewLoadListRecordCount: overlay.netNewRecordCount,
            texturesInInitial: true
        )
        let sources = try buildMergedSources(
            baseSources: initialSources,
            mappedEntries: initialEntries + inlineTextureEntries,
            stringMergeEntries: stringMergeEntries,
            customizationPresetMergeEntries: customizationPresetMergeEntries,
            registryMergeEntries: registryMergeEntries,
            loadListData: loadListData,
            requirePakLoadList: true
        )
        if shouldValidateMergedReferences(changedEntries: initialEntries + registryMergeEntries) {
            try ModReferenceValidator.validateInitialSources(
                sources,
                validateClassLocalReferences: false
            )
        }
        let written = try PakWriter.writeArchive(fileSources: sources, to: outputInitialPak)
        if verifyOutput {
            let writtenArchive = try PakReader.readArchive(at: outputInitialPak)
            let basicIssues = try PakVerifier.verifyBasic(writtenArchive)
            if !basicIssues.isEmpty {
                throw ModMergeError.verificationFailed(name: "verify-basic", issues: basicIssues)
            }
            let layoutIssues = try PakVerifier.verifySnowPakLayout(writtenArchive)
            if !layoutIssues.isEmpty {
                throw ModMergeError.verificationFailed(name: "verify-snowpak-layout", issues: layoutIssues)
            }
        }
        let result = ModMergeResult(
            plan: plan,
            outputURL: outputInitialPak,
            outputTexturesURL: nil,
            outputSharedTexturesURL: nil,
            writtenEntryCount: written,
            writtenTextureEntryCount: nil,
            writtenSharedTextureEntryCount: nil
        )
        try writeReportIfNeeded(result, to: reportURL)
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

    private static func partitionSemanticMergeEntries(
        _ entries: [ModMappedEntry]
    ) throws -> (
        regularEntries: [ModMappedEntry],
        stringMergeEntries: [ModMappedEntry],
        customizationPresetMergeEntries: [ModMappedEntry],
        registryMergeEntries: [ModMappedEntry]
    ) {
        var regularEntries: [ModMappedEntry] = []
        var stringEntriesByName: [String: ModMappedEntry] = [:]
        var stringEntryNames: [String] = []
        var customizationEntriesByName: [String: ModMappedEntry] = [:]
        var customizationEntryNames: [String] = []
        var registryEntriesByName: [String: ModMappedEntry] = [:]
        var registryEntryNames: [String] = []

        for entry in entries {
            if isStringMergeEntry(entry) {
                if let existing = stringEntriesByName[entry.internalName] {
                    let mergedData = try ModStringTable.merge(
                        baseData: existing.data,
                        modData: entry.data,
                        path: entry.internalName
                    )
                    stringEntriesByName[entry.internalName] = ModMappedEntry(
                        archiveURL: existing.archiveURL,
                        originalName: existing.originalName,
                        internalName: existing.internalName,
                        targetArchive: existing.targetArchive,
                        data: mergedData
                    )
                } else {
                    stringEntryNames.append(entry.internalName)
                    stringEntriesByName[entry.internalName] = entry
                }
                continue
            }

            if isCustomizationPresetMergeEntry(entry) {
                if let existing = customizationEntriesByName[entry.internalName] {
                    let mergedData = try ModCustomizationPreset.merge(
                        baseData: existing.data,
                        modData: entry.data,
                        path: entry.internalName
                    )
                    customizationEntriesByName[entry.internalName] = ModMappedEntry(
                        archiveURL: existing.archiveURL,
                        originalName: existing.originalName,
                        internalName: existing.internalName,
                        targetArchive: existing.targetArchive,
                        data: mergedData
                    )
                } else {
                    let mergedData = try ModCustomizationPreset.merge(
                        baseData: Data("<TruckSet/>".utf8),
                        modData: entry.data,
                        path: entry.internalName
                    )
                    customizationEntryNames.append(entry.internalName)
                    customizationEntriesByName[entry.internalName] = ModMappedEntry(
                        archiveURL: entry.archiveURL,
                        originalName: entry.originalName,
                        internalName: entry.internalName,
                        targetArchive: entry.targetArchive,
                        data: mergedData
                    )
                }
                continue
            }

            if isRegistryMergeEntry(entry) {
                if let existing = registryEntriesByName[entry.internalName] {
                    let mergedData = try ModRegistryXMLMerge.merge(
                        baseData: existing.data,
                        modData: entry.data,
                        path: entry.internalName
                    )
                    registryEntriesByName[entry.internalName] = ModMappedEntry(
                        archiveURL: existing.archiveURL,
                        originalName: existing.originalName,
                        internalName: existing.internalName,
                        targetArchive: existing.targetArchive,
                        data: mergedData
                    )
                } else {
                    registryEntryNames.append(entry.internalName)
                    registryEntriesByName[entry.internalName] = entry
                }
                continue
            }

            regularEntries.append(entry)
        }

        let stringMergeEntries = stringEntryNames
            .compactMap { stringEntriesByName[$0] }
            .sorted { $0.internalName < $1.internalName }
        let customizationPresetMergeEntries = customizationEntryNames
            .compactMap { customizationEntriesByName[$0] }
            .sorted { $0.internalName < $1.internalName }
        let registryMergeEntries = registryEntryNames
            .compactMap { registryEntriesByName[$0] }
            .sorted { $0.internalName < $1.internalName }
        return (regularEntries, stringMergeEntries, customizationPresetMergeEntries, registryMergeEntries)
    }

    private static func combinedExperimentalTextureEntries(
        _ entries: [ModMappedEntry]
    ) throws -> [ModMappedEntry] {
        let retargeted = entries.map {
            ModMappedEntry(
                archiveURL: $0.archiveURL,
                originalName: $0.originalName,
                internalName: $0.internalName,
                targetArchive: .sharedTextures,
                data: $0.data,
                localExtraField: $0.localExtraField,
                centralExtraField: $0.centralExtraField,
                compressedPayload: $0.compressedPayload
            )
        }
        return try resolveMappedDuplicates(retargeted).entries
    }

    private static func isStringMergeEntry(_ entry: ModMappedEntry) -> Bool {
        entry.targetArchive == .initial
            && entry.internalName.hasPrefix("[strings]\\")
            && entry.internalName.hasSuffix(".str")
    }

    private static func isCustomizationPresetMergeEntry(_ entry: ModMappedEntry) -> Bool {
        entry.targetArchive == .initial
            && entry.internalName == ModCustomizationPreset.internalName
    }

    private static func isRegistryMergeEntry(_ entry: ModMappedEntry) -> Bool {
        entry.targetArchive == .initial
            && ModRegistryXMLMerge.isSupportedRegistryPath(entry.internalName)
    }

    private static func shouldValidateMergedReferences(changedEntries: [ModMappedEntry]) -> Bool {
        changedEntries.contains { entry in
            let path = entry.internalName.lowercased().replacingOccurrences(of: "/", with: "\\")
            return path.hasSuffix(".xml")
                && (path.contains("\\classes\\trucks\\")
                    || path.contains("\\classes\\wheels\\")
                    || path.contains("\\classes\\engines\\")
                    || path.contains("\\classes\\gearboxes\\")
                    || path.contains("\\classes\\suspensions\\")
                    || path.contains("\\classes\\winches\\"))
        }
    }

    private static func buildMergedSources(
        baseArchive: PakArchive,
        mappedEntries: [ModMappedEntry],
        stringMergeEntries: [ModMappedEntry] = [],
        customizationPresetMergeEntries: [ModMappedEntry] = [],
        registryMergeEntries: [ModMappedEntry] = [],
        loadListData: Data?,
        requirePakLoadList: Bool
    ) throws -> [PakFileSource] {
        let mappedByName = Dictionary(uniqueKeysWithValues: mappedEntries.map { ($0.internalName, $0) })
        let stringMergeByName = Dictionary(uniqueKeysWithValues: stringMergeEntries.map { ($0.internalName, $0) })
        let customizationPresetMergeByName = Dictionary(uniqueKeysWithValues: customizationPresetMergeEntries.map { ($0.internalName, $0) })
        let registryMergeByName = Dictionary(uniqueKeysWithValues: registryMergeEntries.map { ($0.internalName, $0) })
        var sources: [PakFileSource] = []
        sources.reserveCapacity(
            baseArchive.entries.count
                + mappedEntries.count
                + stringMergeEntries.count
                + customizationPresetMergeEntries.count
                + registryMergeEntries.count
        )

        for entry in baseArchive.entries {
            if entry.name == LoadListConstants.manifestEntryName, let loadListData {
                sources.append(PakFileSource(internalName: entry.name, data: loadListData))
                continue
            }
            if let mapped = mappedByName[entry.name] {
                sources.append(pakFileSource(for: mapped))
                continue
            }
            let payload = try PakReader.readUncompressedPayload(entry: entry, in: baseArchive)
            if let stringMerge = stringMergeByName[entry.name] {
                let mergedPayload = try ModStringTable.merge(
                    baseData: payload,
                    modData: stringMerge.data,
                    path: entry.name
                )
                sources.append(PakFileSource(internalName: entry.name, data: mergedPayload))
                continue
            }
            if let customizationPresetMerge = customizationPresetMergeByName[entry.name] {
                let mergedPayload = try ModCustomizationPreset.merge(
                    baseData: payload,
                    modData: customizationPresetMerge.data,
                    path: entry.name
                )
                sources.append(PakFileSource(internalName: entry.name, data: mergedPayload))
                continue
            }
            if let registryMerge = registryMergeByName[entry.name] {
                let mergedPayload = try ModRegistryXMLMerge.merge(
                    baseData: payload,
                    modData: registryMerge.data,
                    path: entry.name
                )
                sources.append(PakFileSource(internalName: entry.name, data: mergedPayload))
                continue
            }
            sources.append(PakFileSource(internalName: entry.name, data: payload))
        }

        let baseNames = Set(baseArchive.entries.map(\.name))
        for mapped in mappedEntries where !baseNames.contains(mapped.internalName) {
            sources.append(pakFileSource(for: mapped))
        }
        for stringMerge in stringMergeEntries where !baseNames.contains(stringMerge.internalName) {
            sources.append(PakFileSource(internalName: stringMerge.internalName, data: stringMerge.data))
        }
        for customizationPresetMerge in customizationPresetMergeEntries where !baseNames.contains(customizationPresetMerge.internalName) {
            sources.append(PakFileSource(internalName: customizationPresetMerge.internalName, data: customizationPresetMerge.data))
        }
        for registryMerge in registryMergeEntries where !baseNames.contains(registryMerge.internalName) {
            sources.append(PakFileSource(internalName: registryMerge.internalName, data: registryMerge.data))
        }

        return try PakDirectoryScanner.sortedPackSources(sources, requirePakLoadList: requirePakLoadList)
    }

    private static func buildMergedSources(
        baseSources: [PakFileSource],
        mappedEntries: [ModMappedEntry],
        stringMergeEntries: [ModMappedEntry] = [],
        customizationPresetMergeEntries: [ModMappedEntry] = [],
        registryMergeEntries: [ModMappedEntry] = [],
        loadListData: Data?,
        requirePakLoadList: Bool
    ) throws -> [PakFileSource] {
        let mappedByName = Dictionary(uniqueKeysWithValues: mappedEntries.map { ($0.internalName, $0) })
        let stringMergeByName = Dictionary(uniqueKeysWithValues: stringMergeEntries.map { ($0.internalName, $0) })
        let customizationPresetMergeByName = Dictionary(uniqueKeysWithValues: customizationPresetMergeEntries.map { ($0.internalName, $0) })
        let registryMergeByName = Dictionary(uniqueKeysWithValues: registryMergeEntries.map { ($0.internalName, $0) })
        var sources: [PakFileSource] = []
        sources.reserveCapacity(
            baseSources.count
                + mappedEntries.count
                + stringMergeEntries.count
                + customizationPresetMergeEntries.count
                + registryMergeEntries.count
        )

        for base in baseSources {
            if base.internalName == LoadListConstants.manifestEntryName, let loadListData {
                sources.append(PakFileSource(internalName: base.internalName, data: loadListData))
                continue
            }
            if let mapped = mappedByName[base.internalName] {
                sources.append(pakFileSource(for: mapped))
                continue
            }
            let payload = try base.readData()
            if let stringMerge = stringMergeByName[base.internalName] {
                let mergedPayload = try ModStringTable.merge(
                    baseData: payload,
                    modData: stringMerge.data,
                    path: base.internalName
                )
                sources.append(PakFileSource(internalName: base.internalName, data: mergedPayload))
                continue
            }
            if let customizationPresetMerge = customizationPresetMergeByName[base.internalName] {
                let mergedPayload = try ModCustomizationPreset.merge(
                    baseData: payload,
                    modData: customizationPresetMerge.data,
                    path: base.internalName
                )
                sources.append(PakFileSource(internalName: base.internalName, data: mergedPayload))
                continue
            }
            if let registryMerge = registryMergeByName[base.internalName] {
                let mergedPayload = try ModRegistryXMLMerge.merge(
                    baseData: payload,
                    modData: registryMerge.data,
                    path: base.internalName
                )
                sources.append(PakFileSource(internalName: base.internalName, data: mergedPayload))
                continue
            }
            sources.append(PakFileSource(
                internalName: base.internalName,
                data: payload,
                localExtraField: base.localExtraField,
                centralExtraField: base.centralExtraField
            ))
        }

        let baseNames = Set(baseSources.map(\.internalName))
        for mapped in mappedEntries where !baseNames.contains(mapped.internalName) {
            sources.append(pakFileSource(for: mapped))
        }
        for stringMerge in stringMergeEntries where !baseNames.contains(stringMerge.internalName) {
            sources.append(PakFileSource(internalName: stringMerge.internalName, data: stringMerge.data))
        }
        for customizationPresetMerge in customizationPresetMergeEntries where !baseNames.contains(customizationPresetMerge.internalName) {
            sources.append(PakFileSource(internalName: customizationPresetMerge.internalName, data: customizationPresetMerge.data))
        }
        for registryMerge in registryMergeEntries where !baseNames.contains(registryMerge.internalName) {
            sources.append(PakFileSource(internalName: registryMerge.internalName, data: registryMerge.data))
        }

        return try PakDirectoryScanner.sortedPackSources(sources, requirePakLoadList: requirePakLoadList)
    }

    private static func pakFileSource(for entry: ModMappedEntry) -> PakFileSource {
        if let compressedPayload = entry.compressedPayload {
            return PakFileSource(
                internalName: entry.internalName,
                compressedPayload: compressedPayload,
                localExtraField: entry.localExtraField,
                centralExtraField: entry.centralExtraField
            )
        }

        return PakFileSource(
            internalName: entry.internalName,
            data: entry.data,
            localExtraField: entry.localExtraField,
            centralExtraField: entry.centralExtraField
        )
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
