import Foundation

public enum CacheBlockReader {
    public static func readArchive(at url: URL) throws -> CacheBlockArchive {
        try readArchive(data: Data(contentsOf: url), url: url)
    }

    public static func readArchive(data: Data, url: URL?) throws -> CacheBlockArchive {
        var reader = BinaryReader(data: data)
        let signature = try reader.readBytes(count: CacheBlockConstants.signature.count)
        guard signature == CacheBlockConstants.signature else {
            throw CacheBlockError.invalidHeader
        }

        try readMarkerInt32(&reader, field: "header version", expected: 1)
        try readMarkerUInt8(&reader, field: "header marker", expected: 1)

        let entryCount = try reader.readInt32()
        guard entryCount >= 0 else {
            throw CacheBlockError.invalidEntryCount(entryCount)
        }
        let count = Int(entryCount)

        try readMarkerInt32(&reader, field: "header table count", expected: 4)
        try readMarkerUInt8(&reader, field: "names marker", expected: 1)

        var names: [String] = []
        names.reserveCapacity(count)
        for _ in 0..<count {
            names.append(try readLengthPrefixedName(&reader))
        }
        try CacheBlockPath.validateInternalNames(names)

        try readMarkerUInt8(&reader, field: "offsets marker", expected: 1)
        var offsets: [Int64] = []
        offsets.reserveCapacity(count)
        for _ in 0..<count {
            offsets.append(try reader.readInt64())
        }

        try readMarkerUInt8(&reader, field: "sizes marker", expected: 1)
        var sizes: [Int32] = []
        sizes.reserveCapacity(count)
        for _ in 0..<count {
            sizes.append(try reader.readInt32())
        }

        try readMarkerUInt8(&reader, field: "zeroes marker", expected: 1)
        var zeroes: [Int32] = []
        zeroes.reserveCapacity(count)
        for _ in 0..<count {
            zeroes.append(try reader.readInt32())
        }

        let baseOffset = reader.offset
        let entries = try (0..<count).map { index in
            let name = names[index]
            let offset = offsets[index]
            let size = sizes[index]
            let zero = zeroes[index]

            guard offset >= 0 else {
                throw CacheBlockError.negativeOffset(entry: name, offset: offset)
            }
            guard size >= 0 else {
                throw CacheBlockError.negativeSize(entry: name, size: size)
            }
            guard zero == 0 else {
                throw CacheBlockError.invalidMarker(field: "zero for \(name)", expected: "0", actual: "\(zero)")
            }

            let start = baseOffset + Int(offset)
            let end = start + Int(size)
            guard start >= baseOffset, start <= end, end <= data.count else {
                throw CacheBlockError.payloadOutOfBounds(entry: name)
            }

            return CacheBlockEntry(
                internalName: name,
                externalPath: try CacheBlockPath.externalPath(forInternalName: name),
                relativeOffset: offset,
                size: size,
                zero: zero
            )
        }

        return CacheBlockArchive(url: url, data: data, entries: entries, baseOffset: baseOffset)
    }

    public static func readPayload(entry: CacheBlockEntry, in archive: CacheBlockArchive) throws -> Data {
        guard entry.relativeOffset >= 0, entry.size >= 0 else {
            throw CacheBlockError.payloadOutOfBounds(entry: entry.internalName)
        }

        let start = archive.baseOffset + Int(entry.relativeOffset)
        let end = start + Int(entry.size)
        guard start >= archive.baseOffset, start <= end, end <= archive.data.count else {
            throw CacheBlockError.payloadOutOfBounds(entry: entry.internalName)
        }

        return archive.data.subdata(in: start..<end)
    }

    private static func readLengthPrefixedName(_ reader: inout BinaryReader) throws -> String {
        let length = try reader.readInt32()
        guard length >= 0 else {
            throw CacheBlockError.invalidStringLength(length)
        }
        return try CP437.decode(try reader.readBytes(count: Int(length)))
    }

    private static func readMarkerInt32(_ reader: inout BinaryReader, field: String, expected: Int32) throws {
        let actual = try reader.readInt32()
        guard actual == expected else {
            throw CacheBlockError.invalidMarker(field: field, expected: "\(expected)", actual: "\(actual)")
        }
    }

    private static func readMarkerUInt8(_ reader: inout BinaryReader, field: String, expected: UInt8) throws {
        let actual = try reader.readBytes(count: 1)[0]
        guard actual == expected else {
            throw CacheBlockError.invalidMarker(field: field, expected: "\(expected)", actual: "\(actual)")
        }
    }
}
