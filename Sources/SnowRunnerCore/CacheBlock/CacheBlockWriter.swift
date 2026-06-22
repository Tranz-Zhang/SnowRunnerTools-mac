import Foundation

public enum CacheBlockWriter {
    @discardableResult
    public static func writeArchive(fromDirectory directory: URL, to outputURL: URL, mixed: Bool = false) throws -> Int {
        let sources = try CacheBlockDirectoryScanner.scan(rootDirectory: directory, mixed: mixed)
        return try writeArchive(fileSources: sources, to: outputURL)
    }

    @discardableResult
    public static func writeArchive(fileSources: [CacheBlockFileSource], to outputURL: URL) throws -> Int {
        try CacheBlockPath.validateInternalNames(fileSources.map(\.internalName))

        var writer = BinaryWriter()
        writer.appendBytes(CacheBlockConstants.signature)
        writer.appendInt32(1)
        writer.appendUInt8(1)
        writer.appendInt32(try checkedInt32("entry count", UInt64(fileSources.count)))
        writer.appendInt32(4)
        writer.appendUInt8(1)

        let nameBytes = try fileSources.map { try CP437.encode($0.internalName) }
        for bytes in nameBytes {
            writer.appendInt32(try checkedInt32("string length", UInt64(bytes.count)))
            writer.appendBytes(bytes)
        }

        let payloads = try fileSources.map { try Data(contentsOf: $0.fileURL) }

        writer.appendUInt8(1)
        var relativeOffset: Int64 = 0
        for payload in payloads {
            writer.appendInt64(relativeOffset)
            relativeOffset += Int64(payload.count)
        }

        writer.appendUInt8(1)
        for payload in payloads {
            writer.appendInt32(try checkedInt32("payload size", UInt64(payload.count)))
        }

        writer.appendUInt8(1)
        for _ in fileSources {
            writer.appendInt32(0)
        }

        for payload in payloads {
            writer.appendData(payload)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try writer.data.write(to: outputURL, options: .atomic)
        return fileSources.count
    }

    private static func checkedInt32(_ field: String, _ value: UInt64) throws -> Int32 {
        guard value <= UInt64(Int32.max) else {
            throw CacheBlockError.valueExceedsInt32(field: field, value: value)
        }
        return Int32(value)
    }
}
