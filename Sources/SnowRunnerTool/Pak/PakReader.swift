import Foundation
import zlib

public enum PakReaderError: Error, CustomStringConvertible {
    case signatureNotFound(String)
    case invalidSignature(expected: UInt32, actual: UInt32, offset: Int)
    case unsupportedCompressionMethod(UInt16)
    case zip64Unsupported
    case multiDiskUnsupported
    case invalidPayloadRange(String)
    case crcMismatch(entry: String, expected: UInt32, actual: UInt32)

    public var description: String {
        switch self {
        case let .signatureNotFound(name):
            return "Signature not found: \(name)"
        case let .invalidSignature(expected, actual, offset):
            return "Invalid signature at offset \(offset): expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))"
        case let .unsupportedCompressionMethod(method):
            return "Unsupported compression method \(method)"
        case .zip64Unsupported:
            return "ZIP64 archives are not supported"
        case .multiDiskUnsupported:
            return "Multi-disk ZIP archives are not supported"
        case let .invalidPayloadRange(entry):
            return "Invalid payload range for \(entry)"
        case let .crcMismatch(entry, expected, actual):
            return "CRC mismatch for \(entry): expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))"
        }
    }
}

public enum PakReader {
    public static func readArchive(at url: URL) throws -> PakArchive {
        let data = try Data(contentsOf: url)
        let eocd = try readEOCD(in: data)
        let centralEntries = try readCentralDirectory(in: data, eocd: eocd)
        let localEntries = try readLocalHeaders(in: data)
        let entries = try mergeCentralEntries(centralEntries, with: localEntries)

        return PakArchive(
            url: url,
            data: data,
            entries: entries,
            localEntries: localEntries,
            centralDirectoryOffset: eocd.centralDirectoryOffset,
            centralDirectorySize: eocd.centralDirectorySize,
            archiveCommentLength: eocd.commentLength,
            isZip64: false
        )
    }

    public static func readUncompressedPayload(entry: PakEntry, in archive: PakArchive) throws -> Data {
        let payload = try compressedPayload(entry: entry, in: archive)

        switch entry.compressionMethod {
        case .stored:
            guard payload.count == Int(entry.uncompressedSize) else {
                throw PakReaderError.invalidPayloadRange(entry.name)
            }
            return payload
        case .deflated:
            return try PakInflater.inflateRawDeflate(payload, expectedSize: entry.uncompressedSize)
        }
    }

    public static func validatePayloadCRCs(in archive: PakArchive) throws {
        for entry in archive.entries {
            let payload = try readUncompressedPayload(entry: entry, in: archive)
            let actual = payload.withUnsafeBytes { buffer in
                crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(payload.count))
            }
            guard UInt32(actual) == entry.crc32 else {
                throw PakReaderError.crcMismatch(entry: entry.name, expected: entry.crc32, actual: UInt32(actual))
            }
            guard payload.count == Int(entry.uncompressedSize) else {
                throw PakReaderError.invalidPayloadRange(entry.name)
            }
        }
    }

    private static func compressedPayload(entry: PakEntry, in archive: PakArchive) throws -> Data {
        let start = entry.dataOffset
        let end = start + Int(entry.compressedSize)
        guard start >= 0, end <= archive.data.count, start <= end else {
            throw PakReaderError.invalidPayloadRange(entry.name)
        }

        return archive.data.subdata(in: start..<end)
    }

    private static func readEOCD(in data: Data) throws -> EndOfCentralDirectory {
        let offset = try findEndOfCentralDirectory(in: data)
        var reader = BinaryReader(data: data, offset: offset)
        let signature = try reader.readUInt32()
        guard signature == ZipSignature.endOfCentralDirectory else {
            throw PakReaderError.invalidSignature(expected: ZipSignature.endOfCentralDirectory, actual: signature, offset: offset)
        }

        let diskNumber = try reader.readUInt16()
        let centralDirectoryStartDisk = try reader.readUInt16()
        let entriesOnDisk = try reader.readUInt16()
        let totalEntries = try reader.readUInt16()
        let centralDirectorySize = try reader.readUInt32()
        let centralDirectoryOffset = try reader.readUInt32()
        let commentLength = try reader.readUInt16()

        guard diskNumber == 0, centralDirectoryStartDisk == 0, entriesOnDisk == totalEntries else {
            throw PakReaderError.multiDiskUnsupported
        }

        guard totalEntries != UInt16.max,
              centralDirectorySize != UInt32.max,
              centralDirectoryOffset != UInt32.max
        else {
            throw PakReaderError.zip64Unsupported
        }

        if containsZip64SignatureNearEOCD(in: data, eocdOffset: offset) {
            throw PakReaderError.zip64Unsupported
        }

        try reader.skip(Int(commentLength))

        return EndOfCentralDirectory(
            entryCount: totalEntries,
            centralDirectorySize: centralDirectorySize,
            centralDirectoryOffset: centralDirectoryOffset,
            commentLength: commentLength
        )
    }

    private static func findEndOfCentralDirectory(in data: Data) throws -> Int {
        let minimumEOCDSize = 22
        guard data.count >= minimumEOCDSize else {
            throw PakReaderError.signatureNotFound("EOCD")
        }

        let maxCommentLength = Int(UInt16.max)
        let lowerBound = max(0, data.count - minimumEOCDSize - maxCommentLength)
        var offset = data.count - minimumEOCDSize

        while offset >= lowerBound {
            if UInt32(littleEndianBytes: data[offset..<offset + 4]) == ZipSignature.endOfCentralDirectory {
                return offset
            }
            offset -= 1
        }

        throw PakReaderError.signatureNotFound("EOCD")
    }

    private static func containsZip64SignatureNearEOCD(in data: Data, eocdOffset: Int) -> Bool {
        let start = max(0, eocdOffset - 128)
        guard start < eocdOffset else {
            return false
        }

        var offset = start
        while offset + 4 <= eocdOffset {
            let signature = UInt32(littleEndianBytes: data[offset..<offset + 4])
            if signature == ZipSignature.zip64EndOfCentralDirectory || signature == ZipSignature.zip64Locator {
                return true
            }
            offset += 1
        }
        return false
    }

    private static func readCentralDirectory(in data: Data, eocd: EndOfCentralDirectory) throws -> [PakEntry] {
        var reader = BinaryReader(data: data, offset: Int(eocd.centralDirectoryOffset))
        var entries: [PakEntry] = []

        for _ in 0..<eocd.entryCount {
            let headerOffset = reader.offset
            let signature = try reader.readUInt32()
            guard signature == ZipSignature.centralDirectoryHeader else {
                throw PakReaderError.invalidSignature(expected: ZipSignature.centralDirectoryHeader, actual: signature, offset: headerOffset)
            }

            let versionMadeBy = try reader.readUInt16()
            let versionNeeded = try reader.readUInt16()
            let flags = try reader.readUInt16()
            let methodRaw = try reader.readUInt16()
            guard let method = ZipCompressionMethod(rawValue: methodRaw) else {
                throw PakReaderError.unsupportedCompressionMethod(methodRaw)
            }
            let dosTime = try reader.readUInt16()
            let dosDate = try reader.readUInt16()
            let crc32 = try reader.readUInt32()
            let compressedSize = try reader.readUInt32()
            let uncompressedSize = try reader.readUInt32()
            let nameLength = try reader.readUInt16()
            let extraLength = try reader.readUInt16()
            let commentLength = try reader.readUInt16()
            _ = try reader.readUInt16() // disk number start
            _ = try reader.readUInt16() // internal attributes
            let externalAttributes = try reader.readUInt32()
            let localHeaderOffset = try reader.readUInt32()
            let name = try CP437.decode(try reader.readBytes(count: Int(nameLength)))
            let centralExtraField = try reader.readBytes(count: Int(extraLength))
            try reader.skip(Int(commentLength))

            entries.append(PakEntry(
                name: name,
                compressionMethod: method,
                generalPurposeBitFlag: flags,
                crc32: crc32,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                versionNeeded: versionNeeded,
                dosTime: dosTime,
                dosDate: dosDate,
                localHeaderOffset: localHeaderOffset,
                dataOffset: 0,
                localExtraFieldLength: 0,
                centralVersionMadeBy: versionMadeBy,
                centralExtraFieldLength: extraLength,
                centralExtraField: Data(centralExtraField),
                centralFileCommentLength: commentLength,
                centralExternalAttributes: externalAttributes
            ))
        }

        return entries
    }

    private static func readLocalHeaders(in data: Data) throws -> [PakEntry] {
        var reader = BinaryReader(data: data)
        var entries: [PakEntry] = []

        while reader.offset + 4 <= data.count {
            let headerOffset = reader.offset
            let signature = try reader.readUInt32()
            guard signature == ZipSignature.localFileHeader else {
                break
            }

            let versionNeeded = try reader.readUInt16()
            let flags = try reader.readUInt16()
            let methodRaw = try reader.readUInt16()
            guard let method = ZipCompressionMethod(rawValue: methodRaw) else {
                throw PakReaderError.unsupportedCompressionMethod(methodRaw)
            }
            let dosTime = try reader.readUInt16()
            let dosDate = try reader.readUInt16()
            let crc32 = try reader.readUInt32()
            let compressedSize = try reader.readUInt32()
            let uncompressedSize = try reader.readUInt32()
            let nameLength = try reader.readUInt16()
            let extraLength = try reader.readUInt16()
            let name = try CP437.decode(try reader.readBytes(count: Int(nameLength)))
            let localExtraField = try reader.readBytes(count: Int(extraLength))
            let dataOffset = reader.offset
            try reader.skip(Int(compressedSize))

            entries.append(PakEntry(
                name: name,
                compressionMethod: method,
                generalPurposeBitFlag: flags,
                crc32: crc32,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                versionNeeded: versionNeeded,
                dosTime: dosTime,
                dosDate: dosDate,
                localHeaderOffset: UInt32(headerOffset),
                dataOffset: dataOffset,
                localExtraFieldLength: extraLength,
                localExtraField: Data(localExtraField),
                centralVersionMadeBy: nil,
                centralExtraFieldLength: nil,
                centralFileCommentLength: nil,
                centralExternalAttributes: nil
            ))
        }

        return entries
    }

    private static func mergeCentralEntries(_ centralEntries: [PakEntry], with localEntries: [PakEntry]) throws -> [PakEntry] {
        let localByOffset = Dictionary(uniqueKeysWithValues: localEntries.map { ($0.localHeaderOffset, $0) })

        return try centralEntries.map { central in
            guard let local = localByOffset[central.localHeaderOffset] else {
                throw PakReaderError.signatureNotFound("local header for \(central.name)")
            }
            guard central.name == local.name,
                  central.compressionMethod == local.compressionMethod,
                  central.generalPurposeBitFlag == local.generalPurposeBitFlag,
                  central.crc32 == local.crc32,
                  central.compressedSize == local.compressedSize,
                  central.uncompressedSize == local.uncompressedSize,
                  central.versionNeeded == local.versionNeeded,
                  central.dosTime == local.dosTime,
                  central.dosDate == local.dosDate
            else {
                throw PakReaderError.signatureNotFound("matching local header metadata for \(central.name)")
            }

            return PakEntry(
                name: central.name,
                compressionMethod: central.compressionMethod,
                generalPurposeBitFlag: central.generalPurposeBitFlag,
                crc32: central.crc32,
                compressedSize: central.compressedSize,
                uncompressedSize: central.uncompressedSize,
                versionNeeded: central.versionNeeded,
                dosTime: central.dosTime,
                dosDate: central.dosDate,
                localHeaderOffset: central.localHeaderOffset,
                dataOffset: local.dataOffset,
                localExtraFieldLength: local.localExtraFieldLength,
                localExtraField: local.localExtraField,
                centralVersionMadeBy: central.centralVersionMadeBy,
                centralExtraFieldLength: central.centralExtraFieldLength,
                centralExtraField: central.centralExtraField,
                centralFileCommentLength: central.centralFileCommentLength,
                centralExternalAttributes: central.centralExternalAttributes
            )
        }
    }
}

private struct EndOfCentralDirectory {
    let entryCount: UInt16
    let centralDirectorySize: UInt32
    let centralDirectoryOffset: UInt32
    let commentLength: UInt16
}

private extension UInt32 {
    init(littleEndianBytes bytes: Data.SubSequence) {
        var result: UInt32 = 0
        for (shift, byte) in bytes.enumerated() {
            result |= UInt32(byte) << UInt32(shift * 8)
        }
        self = result
    }
}
