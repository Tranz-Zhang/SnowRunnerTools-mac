import Foundation

public enum PakReaderError: Error, CustomStringConvertible {
    case signatureNotFound(String)
    case invalidSignature(expected: UInt32, actual: UInt32, offset: Int)
    case unsupportedCompressionMethod(UInt16)
    case zip64Unsupported
    case multiDiskUnsupported

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
        }
    }
}

public enum PakReader {
    public static func readArchive(at url: URL) throws -> PakArchive {
        let data = try Data(contentsOf: url)
        let eocd = try readEOCD(in: data)
        let entries = try readCentralDirectory(in: data, eocd: eocd)

        return PakArchive(
            url: url,
            data: data,
            entries: entries,
            localEntries: [],
            centralDirectoryOffset: eocd.centralDirectoryOffset,
            centralDirectorySize: eocd.centralDirectorySize,
            archiveCommentLength: eocd.commentLength,
            isZip64: false
        )
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
            try reader.skip(Int(extraLength) + Int(commentLength))

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
                centralFileCommentLength: commentLength,
                centralExternalAttributes: externalAttributes
            ))
        }

        return entries
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
