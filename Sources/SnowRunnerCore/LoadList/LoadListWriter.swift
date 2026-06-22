import Foundation

public enum LoadListWriter {
    @discardableResult
    public static func writeManifest(_ manifest: LoadListManifest, to url: URL) throws -> Int {
        let data = try encodeManifest(manifest)
        try data.write(to: url)
        return data.count
    }

    public static func encodeManifest(_ manifest: LoadListManifest) throws -> Data {
        guard manifest.versionTag == LoadListConstants.versionTag else {
            throw LoadListError.invalidVersionTag(manifest.versionTag)
        }

        let entries = manifest.entries
        guard entries.count >= 2,
              entries.first?.kind == .start,
              entries.last?.kind == .end
        else {
            throw LoadListError.invalidStartEntry
        }

        var writer = BinaryWriter()

        // Header (14 bytes)
        writer.appendUInt32(manifest.versionTag)
        writer.appendUInt8(LoadListConstants.marker)
        writer.appendUInt32(UInt32(entries.count))
        writer.appendUInt32(manifest.headerTail)
        writer.appendUInt8(LoadListConstants.marker)

        // Entry-types byte array
        for entry in entries {
            writer.appendUInt8(entry.kind.rawValue)
        }
        writer.appendUInt8(LoadListConstants.marker)

        // Dependencies block
        for (i, entry) in entries.enumerated() {
            writer.appendUInt32(UInt32(entry.dependsOn.count))
            writer.appendUInt8(LoadListConstants.marker)
            for dep in entry.dependsOn {
                guard dep >= 0 && Int(dep) < entries.count else {
                    throw LoadListError.invalidDependencyIndex(entry: i, dependency: dep)
                }
                writer.appendInt32(dep)
            }
        }
        writer.appendUInt8(LoadListConstants.marker)

        // Strings block
        for entry in entries {
            try validateStringsCount(entry.strings.count, for: entry.kind)
            guard entry.magicA.count == entry.strings.count else {
                throw LoadListError.invalidEntryStringsCount(kind: "\(entry.kind)", count: entry.magicA.count)
            }
            guard entry.magicB.count == 2 else {
                throw LoadListError.invalidMagicBCount(entry.magicB.count)
            }

            writer.appendUInt32(UInt32(entry.strings.count))
            writer.appendUInt32(UInt32(entry.magicB.count))
            writer.appendBytes(entry.magicA)
            writer.appendBytes(entry.magicB)
            for string in entry.strings {
                let bytes: [UInt8]
                do {
                    bytes = try CP437.encode(string)
                } catch {
                    throw LoadListError.unsupportedNonASCIIString(string)
                }
                writer.appendUInt32(UInt32(bytes.count))
                writer.appendBytes(bytes)
            }
        }

        return writer.data
    }

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
}
