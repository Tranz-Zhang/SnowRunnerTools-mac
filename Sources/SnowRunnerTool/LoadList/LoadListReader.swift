import Foundation

public enum LoadListReader {
    public static func readManifest(from url: URL) throws -> LoadListManifest {
        let data = try Data(contentsOf: url)
        return try readManifest(data: data)
    }

    public static func readManifest(data: Data) throws -> LoadListManifest {
        var reader = BinaryReader(data: data)

        // -------- Header (14 bytes) --------
        let version = try readUInt32OrTruncated(&reader)
        guard version == LoadListConstants.versionTag else {
            throw LoadListError.invalidVersionTag(version)
        }

        try expectMarker(&reader, field: "header[4]")

        let entriesCount = Int(try readUInt32OrTruncated(&reader))
        guard entriesCount >= 2 else {
            throw LoadListError.truncatedManifest
        }

        let headerTail = try readUInt32OrTruncated(&reader)

        try expectMarker(&reader, field: "header[13]")

        // -------- Entry-types byte array --------
        let typeBytes: [UInt8]
        do {
            typeBytes = try reader.readBytes(count: entriesCount)
        } catch {
            throw LoadListError.truncatedManifest
        }

        var kinds: [LoadListEntryKind] = []
        kinds.reserveCapacity(entriesCount)
        for raw in typeBytes {
            guard let kind = LoadListEntryKind(rawValue: raw) else {
                throw LoadListError.invalidEntryType(raw)
            }
            kinds.append(kind)
        }
        guard kinds.first == .start else {
            throw LoadListError.invalidStartEntry
        }
        guard kinds.last == .end else {
            throw LoadListError.invalidEndEntry
        }
        for i in 1..<(entriesCount - 1) {
            let kind = kinds[i]
            guard kind == .stage || kind == .asset else {
                throw LoadListError.invalidEntryType(kind.rawValue)
            }
        }

        try expectMarker(&reader, field: "afterTypes")

        // -------- Dependencies block --------
        var dependsOnPerEntry: [[Int32]] = []
        dependsOnPerEntry.reserveCapacity(entriesCount)
        for i in 0..<entriesCount {
            let count = Int(try readUInt32OrTruncated(&reader))
            guard count >= 0 else {
                throw LoadListError.invalidDependencyIndex(entry: i, dependency: Int32(count))
            }
            try expectMarker(&reader, field: "deps[\(i)]")
            var deps: [Int32] = []
            deps.reserveCapacity(count)
            for _ in 0..<count {
                let value = try readInt32OrTruncated(&reader)
                guard value >= 0 && Int(value) < entriesCount else {
                    throw LoadListError.invalidDependencyIndex(entry: i, dependency: value)
                }
                deps.append(value)
            }
            dependsOnPerEntry.append(deps)
        }

        try expectMarker(&reader, field: "afterDeps")

        // -------- Strings block --------
        var entries: [LoadListEntry] = []
        entries.reserveCapacity(entriesCount)
        for i in 0..<entriesCount {
            let kind = kinds[i]
            let stringsCount = Int(try readInt32OrTruncated(&reader))
            let magicBCount = Int(try readInt32OrTruncated(&reader))

            try validateStringsCount(stringsCount, for: kind)
            guard magicBCount == 2 else {
                throw LoadListError.invalidMagicBCount(magicBCount)
            }

            let magicABytes: [UInt8]
            let magicBBytes: [UInt8]
            do {
                magicABytes = try reader.readBytes(count: stringsCount)
                magicBBytes = try reader.readBytes(count: magicBCount)
            } catch {
                throw LoadListError.truncatedManifest
            }
            for byte in magicABytes where byte != 0x01 {
                throw LoadListError.invalidMagicByte(field: "magicA[\(i)]", expected: 0x01, actual: byte)
            }
            for byte in magicBBytes where byte != 0x01 {
                throw LoadListError.invalidMagicByte(field: "magicB[\(i)]", expected: 0x01, actual: byte)
            }

            var strings: [String] = []
            strings.reserveCapacity(stringsCount)
            for _ in 0..<stringsCount {
                strings.append(try readLengthPrefixedCP437(&reader))
            }

            entries.append(LoadListEntry(
                kind: kind,
                dependsOn: dependsOnPerEntry[i],
                magicA: magicABytes,
                magicB: magicBBytes,
                strings: strings
            ))
        }

        if reader.offset != data.count {
            throw LoadListError.trailingBytes(data.count - reader.offset)
        }

        // -------- Phase grouping --------
        // Per SnowPakTool's CreateEntries, asset entries between Stage[N-1] (or
        // Start) and Stage[N] belong to Stage[N]'s phase tag. Assets that
        // appear after the last Stage (and before End) belong to no phase; the
        // reference manifest does not have any such entries.
        var phaseOrder: [String] = []
        var recordsByPhase: [String: [LoadListRecord]] = [:]
        var pendingAssets: [LoadListEntry] = []
        for entry in entries {
            switch entry.kind {
            case .start, .end:
                continue
            case .asset:
                pendingAssets.append(entry)
            case .stage:
                let phase = entry.strings[0]
                phaseOrder.append(phase)
                recordsByPhase[phase] = pendingAssets.map { asset in
                    let internalName = asset.strings[0]
                    let loader = asset.strings[1]
                    let pakName = asset.strings[2]
                    let json = asset.strings.count >= 4 ? asset.strings[3] : nil
                    return LoadListRecord(
                        manifestPath: internalName,
                        loaderType: loader,
                        sourcePak: pakName,
                        json: json,
                        phase: phase
                    )
                }
                pendingAssets.removeAll(keepingCapacity: true)
            }
        }

        guard phaseOrder == LoadListConstants.phasesInWriteOrder else {
            throw LoadListError.invalidPhaseTag(phaseOrder.joined(separator: ", "))
        }

        return LoadListManifest(
            versionTag: version,
            headerTail: headerTail,
            entries: entries,
            recordsByPhase: recordsByPhase,
            phaseOrder: phaseOrder
        )
    }

    // MARK: - Helpers

    private static func validateStringsCount(_ count: Int, for kind: LoadListEntryKind) throws {
        switch kind {
        case .start, .end:
            guard count == 0 else {
                throw LoadListError.invalidEntryStringsCount(kind: "\(kind)", count: count)
            }
        case .stage:
            guard count == 1 else {
                throw LoadListError.invalidEntryStringsCount(kind: "stage", count: count)
            }
        case .asset:
            guard count == 3 || count == 4 else {
                throw LoadListError.invalidEntryStringsCount(kind: "asset", count: count)
            }
        }
    }

    private static func readLengthPrefixedCP437(_ reader: inout BinaryReader) throws -> String {
        let length = try readInt32OrTruncated(&reader)
        guard length >= 0 else {
            throw LoadListError.invalidStringLength(length)
        }
        let bytes: [UInt8]
        do {
            bytes = try reader.readBytes(count: Int(length))
        } catch {
            throw LoadListError.truncatedManifest
        }
        do {
            return try CP437.decode(bytes)
        } catch {
            throw LoadListError.unsupportedNonASCIIString(String(bytes.map { Character(UnicodeScalar($0)) }))
        }
    }

    private static func expectMarker(_ reader: inout BinaryReader, field: String) throws {
        let value = try readUInt8OrTruncated(&reader)
        guard value == LoadListConstants.marker else {
            throw LoadListError.invalidMarker(field: field, expected: LoadListConstants.marker, actual: value)
        }
    }

    private static func readUInt32OrTruncated(_ reader: inout BinaryReader) throws -> UInt32 {
        do {
            return try reader.readUInt32()
        } catch {
            throw LoadListError.truncatedManifest
        }
    }

    private static func readInt32OrTruncated(_ reader: inout BinaryReader) throws -> Int32 {
        do {
            return try reader.readInt32()
        } catch {
            throw LoadListError.truncatedManifest
        }
    }

    private static func readUInt8OrTruncated(_ reader: inout BinaryReader) throws -> UInt8 {
        do {
            let bytes = try reader.readBytes(count: 1)
            return bytes[0]
        } catch {
            throw LoadListError.truncatedManifest
        }
    }
}
