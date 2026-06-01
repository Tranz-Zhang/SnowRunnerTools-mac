import Foundation

public enum LoadListReader {
    public static func readManifest(from url: URL) throws -> LoadListManifest {
        let data = try Data(contentsOf: url)
        return try readManifest(data: data)
    }

    public static func readManifest(data: Data) throws -> LoadListManifest {
        var reader = BinaryReader(data: data)

        let version = try readUInt32OrTruncated(&reader)
        guard version == LoadListConstants.versionTag else {
            throw LoadListError.invalidVersionTag(version)
        }

        let marker = try readUInt8OrTruncated(&reader)
        guard marker == LoadListConstants.marker else {
            throw LoadListError.invalidMarker(field: "header", expected: LoadListConstants.marker, actual: marker)
        }

        let totalRecordCount = try readUInt32OrTruncated(&reader)
        let headerTail = try readUInt32OrTruncated(&reader)

        let recordFlags: [UInt8]
        do {
            recordFlags = try reader.readBytes(count: Int(totalRecordCount))
        } catch {
            throw LoadListError.truncatedManifest
        }

        let phaseOrder = try scanPhaseTagsInOrder(in: data, startingAt: reader.offset)

        // Task 1: do not yet parse records. Phases are captured as empty
        // record arrays; Task 2 will replace this with the full parser.
        var recordsByPhase: [String: [LoadListRecord]] = [:]
        for phase in phaseOrder {
            recordsByPhase[phase] = []
        }

        return LoadListManifest(
            versionTag: version,
            headerTail: headerTail,
            recordFlags: recordFlags,
            recordsByPhase: recordsByPhase,
            phaseOrder: phaseOrder
        )
    }

    /// Scans the manifest body for each expected phase tag as a length-prefixed
    /// CP437 string and returns them in the order they appear in the bytes. The
    /// returned order must equal `LoadListConstants.phasesInWriteOrder` for a
    /// well-formed manifest; otherwise `LoadListError.invalidPhaseTag` is thrown.
    private static func scanPhaseTagsInOrder(in data: Data, startingAt searchStart: Int) throws -> [String] {
        var observed: [(offset: Int, tag: String)] = []

        for tag in LoadListConstants.phasesInWriteOrder {
            guard let bytes = try? CP437.encode(tag) else {
                throw LoadListError.invalidPhaseTag(tag)
            }
            var prefixed = Data(count: 4)
            let length = UInt32(bytes.count)
            prefixed[0] = UInt8(length & 0xFF)
            prefixed[1] = UInt8((length >> 8) & 0xFF)
            prefixed[2] = UInt8((length >> 16) & 0xFF)
            prefixed[3] = UInt8((length >> 24) & 0xFF)
            prefixed.append(contentsOf: bytes)

            guard let range = data.range(of: prefixed, options: [], in: searchStart..<data.count) else {
                throw LoadListError.invalidPhaseTag(tag)
            }
            observed.append((offset: range.lowerBound, tag: tag))
        }

        let sorted = observed.sorted { $0.offset < $1.offset }
        let order = sorted.map(\.tag)
        guard order == LoadListConstants.phasesInWriteOrder else {
            throw LoadListError.invalidPhaseTag(order.joined(separator: ", "))
        }
        return order
    }

    private static func readUInt32OrTruncated(_ reader: inout BinaryReader) throws -> UInt32 {
        do {
            return try reader.readUInt32()
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
