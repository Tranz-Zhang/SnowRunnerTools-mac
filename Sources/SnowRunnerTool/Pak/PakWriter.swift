import Foundation
import zlib

public enum PakWriter {
    private static let versionNeeded: UInt16 = 0x0014
    private static let versionMadeBy: UInt16 = 0x0314
    private static let generalPurposeBitFlag: UInt16 = 0
    private static let dosTime: UInt16 = 0x1800
    private static let dosDate: UInt16 = 0x0021
    private static let externalAttributes: UInt32 = 0x81B60000

    @discardableResult
    public static func writeArchive(fromDirectory directory: URL, to outputURL: URL) throws -> Int {
        let sources = try PakDirectoryScanner.scan(rootDirectory: directory)
        return try writeArchive(fileSources: sources, to: outputURL)
    }

    @discardableResult
    public static func writeArchive(fileSources: [PakFileSource], to outputURL: URL) throws -> Int {
        guard fileSources.count <= Int(UInt16.max) else {
            throw PakWriterError.entryCountExceedsZip32(fileSources.count)
        }

        var writer = BinaryWriter()
        var records: [WrittenEntry] = []

        for source in fileSources {
            let nameBytes = try checkedNameBytes(source.internalName)
            let uncompressed = try Data(contentsOf: source.fileURL)
            let method = compressionMethod(for: source.internalName)
            let payload = method == .stored ? uncompressed : try PakDeflater.deflateRaw(uncompressed)
            let record = WrittenEntry(
                name: source.internalName,
                nameBytes: nameBytes,
                compressionMethod: method,
                crc32: crc32(for: uncompressed),
                compressedSize: try checkedUInt32("compressed size", UInt64(payload.count)),
                uncompressedSize: try checkedUInt32("uncompressed size", UInt64(uncompressed.count)),
                localHeaderOffset: try checkedUInt32("local header offset", UInt64(writer.data.count))
            )

            appendLocalHeader(record, to: &writer)
            writer.appendData(payload)
            records.append(record)
        }

        let centralDirectoryOffset = try checkedUInt32("central directory offset", UInt64(writer.data.count))
        for record in records {
            appendCentralDirectoryHeader(record, to: &writer)
        }
        let centralDirectorySize = try checkedUInt32(
            "central directory size",
            UInt64(writer.data.count) - UInt64(centralDirectoryOffset)
        )
        appendEndOfCentralDirectory(
            entryCount: UInt16(records.count),
            centralDirectorySize: centralDirectorySize,
            centralDirectoryOffset: centralDirectoryOffset,
            to: &writer
        )

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try writer.data.write(to: outputURL, options: .atomic)
        return records.count
    }

    private static func compressionMethod(for internalName: String) -> ZipCompressionMethod {
        internalName == "pak.load_list" ? .stored : .deflated
    }

    private static func checkedNameBytes(_ name: String) throws -> [UInt8] {
        let bytes = try CP437.encode(name)
        _ = try checkedUInt16("filename length", bytes.count)
        return bytes
    }

    private static func checkedUInt16(_ field: String, _ value: Int) throws -> UInt16 {
        guard value <= Int(UInt16.max) else {
            throw PakWriterError.valueExceedsUInt16(field: field, value: value)
        }
        return UInt16(value)
    }

    private static func checkedUInt32(_ field: String, _ value: UInt64) throws -> UInt32 {
        guard value <= UInt64(UInt32.max) else {
            throw PakWriterError.valueExceedsUInt32(field: field, value: value)
        }
        return UInt32(value)
    }

    private static func crc32(for data: Data) -> UInt32 {
        let value = data.withUnsafeBytes { buffer in
            zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))
        }
        return UInt32(value)
    }

    private static func appendLocalHeader(_ record: WrittenEntry, to writer: inout BinaryWriter) {
        writer.appendUInt32(ZipSignature.localFileHeader)
        writer.appendUInt16(versionNeeded)
        writer.appendUInt16(generalPurposeBitFlag)
        writer.appendUInt16(record.compressionMethod.rawValue)
        writer.appendUInt16(dosTime)
        writer.appendUInt16(dosDate)
        writer.appendUInt32(record.crc32)
        writer.appendUInt32(record.compressedSize)
        writer.appendUInt32(record.uncompressedSize)
        writer.appendUInt16(UInt16(record.nameBytes.count))
        writer.appendUInt16(0)
        writer.appendBytes(record.nameBytes)
    }

    private static func appendCentralDirectoryHeader(_ record: WrittenEntry, to writer: inout BinaryWriter) {
        writer.appendUInt32(ZipSignature.centralDirectoryHeader)
        writer.appendUInt16(versionMadeBy)
        writer.appendUInt16(versionNeeded)
        writer.appendUInt16(generalPurposeBitFlag)
        writer.appendUInt16(record.compressionMethod.rawValue)
        writer.appendUInt16(dosTime)
        writer.appendUInt16(dosDate)
        writer.appendUInt32(record.crc32)
        writer.appendUInt32(record.compressedSize)
        writer.appendUInt32(record.uncompressedSize)
        writer.appendUInt16(UInt16(record.nameBytes.count))
        writer.appendUInt16(0)
        writer.appendUInt16(0)
        writer.appendUInt16(0)
        writer.appendUInt16(0)
        writer.appendUInt32(externalAttributes)
        writer.appendUInt32(record.localHeaderOffset)
        writer.appendBytes(record.nameBytes)
    }

    private static func appendEndOfCentralDirectory(
        entryCount: UInt16,
        centralDirectorySize: UInt32,
        centralDirectoryOffset: UInt32,
        to writer: inout BinaryWriter
    ) {
        writer.appendUInt32(ZipSignature.endOfCentralDirectory)
        writer.appendUInt16(0)
        writer.appendUInt16(0)
        writer.appendUInt16(entryCount)
        writer.appendUInt16(entryCount)
        writer.appendUInt32(centralDirectorySize)
        writer.appendUInt32(centralDirectoryOffset)
        writer.appendUInt16(0)
    }
}

private struct WrittenEntry {
    let name: String
    let nameBytes: [UInt8]
    let compressionMethod: ZipCompressionMethod
    let crc32: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
}
