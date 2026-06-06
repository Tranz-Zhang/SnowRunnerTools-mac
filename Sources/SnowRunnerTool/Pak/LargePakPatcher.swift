import Foundation
import zlib

public struct LargePakPatchEntry: Equatable {
    public let name: String
    public let data: Data
    public let centralExtraField: Data
    public let compressedPayload: PakCompressedPayload?

    public init(
        name: String,
        data: Data,
        centralExtraField: Data = Data(),
        compressedPayload: PakCompressedPayload? = nil
    ) {
        self.name = name
        self.data = data
        self.centralExtraField = centralExtraField
        self.compressedPayload = compressedPayload
    }
}

public struct LargePakIndex: Equatable {
    public let entryNames: [String]

    public var entryCount: Int { entryNames.count }
}

public enum LargePakPatcherError: Error, CustomStringConvertible, Equatable {
    case signatureNotFound(String)
    case invalidSignature(String)
    case multiDiskUnsupported
    case unsupportedCompressionMethod(UInt16)
    case overwriteRequired(paths: [String])
    case conflictingAddition(String)
    case outputPathMatchesInput(String)
    case valueExceedsUInt16(field: String, value: Int)
    case valueExceedsUInt32(field: String, value: UInt64)

    public var description: String {
        switch self {
        case let .signatureNotFound(name):
            return "Signature not found: \(name)"
        case let .invalidSignature(name):
            return "Invalid ZIP signature: \(name)"
        case .multiDiskUnsupported:
            return "Multi-disk ZIP archives are not supported"
        case let .unsupportedCompressionMethod(method):
            return "Unsupported compression method \(method)"
        case let .overwriteRequired(paths):
            return "Mapped mod entries collide with existing shared_textures.pak entries. Re-run with --allow-overwrite to replace them:\n\(paths.prefix(10).joined(separator: "\n"))"
        case let .conflictingAddition(path):
            return "Two patch entries map to \(path) with different bytes"
        case let .outputPathMatchesInput(path):
            return "Output path must be distinct from input PAK: \(path)"
        case let .valueExceedsUInt16(field, value):
            return "\(field) exceeds UInt16: \(value)"
        case let .valueExceedsUInt32(field, value):
            return "\(field) exceeds UInt32: \(value)"
        }
    }
}

public enum LargePakPatcher {
    private static let chunkSize = 8 * 1024 * 1024
    private static let uint16Max = UInt64(UInt16.max)
    private static let uint32Max = UInt64(UInt32.max)
    private static let zip64ExtraFieldID: UInt16 = 0x0001

    public static func readIndex(input: URL) throws -> LargePakIndex {
        let parsed = try readCentralDirectory(at: input)
        return LargePakIndex(entryNames: parsed.entries.map(\.name))
    }

    @discardableResult
    public static func patchArchive(
        input: URL,
        output: URL,
        additions: [LargePakPatchEntry],
        allowOverwrite: Bool,
        forceZip64EndRecords: Bool = false
    ) throws -> Int {
        let inputPath = input.standardizedFileURL.path
        let outputPath = output.standardizedFileURL.path
        if inputPath == outputPath {
            throw LargePakPatcherError.outputPathMatchesInput(outputPath)
        }

        let parsed = try readCentralDirectory(at: input)
        let additionsByName = try uniqueAdditions(additions)
        let existingNames = Set(parsed.entries.map(\.name))
        let collisions = additionsByName.keys.filter { existingNames.contains($0) }.sorted()
        if !collisions.isEmpty && !allowOverwrite {
            throw LargePakPatcherError.overwriteRequired(paths: collisions)
        }

        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let tempOutput = output.deletingLastPathComponent()
            .appendingPathComponent(".\(output.lastPathComponent).tmp-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempOutput.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: tempOutput)
        }

        let inputHandle = try FileHandle(forReadingFrom: input)
        defer { try? inputHandle.close() }
        let outputHandle = try FileHandle(forWritingTo: tempOutput)
        defer { try? outputHandle.close() }

        let localOrder = parsed.entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
        var copiedRecordsByName: [String: LargePakCentralEntry] = [:]
        var outputOffset: UInt64 = 0

        for (index, entry) in localOrder.enumerated() where !additionsByName.keys.contains(entry.name) {
            let end = index + 1 < localOrder.count
                ? localOrder[index + 1].localHeaderOffset
                : parsed.centralDirectoryOffset
            let length = end - entry.localHeaderOffset
            try copyRange(
                inputHandle: inputHandle,
                outputHandle: outputHandle,
                start: entry.localHeaderOffset,
                length: length
            )
            var copied = entry
            copied.localHeaderOffset = outputOffset
            copiedRecordsByName[entry.name] = copied
            outputOffset += length
        }

        var finalRecords: [LargePakCentralEntry] = []
        for entry in parsed.entries where !additionsByName.keys.contains(entry.name) {
            if let copied = copiedRecordsByName[entry.name] {
                finalRecords.append(copied)
            }
        }

        var writtenAdditionNames: Set<String> = []
        for addition in additions {
            guard writtenAdditionNames.insert(addition.name).inserted else { continue }
            let record = try writeNewStoredEntry(addition, offset: outputOffset, outputHandle: outputHandle)
            outputOffset += record.localRecordLength
            finalRecords.append(record)
        }

        let centralDirectoryOffset = outputOffset
        var centralDirectory = BinaryWriter()
        for record in finalRecords {
            try appendCentralDirectoryHeader(record, to: &centralDirectory)
        }
        let centralDirectorySize = UInt64(centralDirectory.data.count)
        try outputHandle.write(contentsOf: centralDirectory.data)
        outputOffset += centralDirectorySize

        let needsZip64 = forceZip64EndRecords
            || UInt64(finalRecords.count) > uint16Max
            || centralDirectoryOffset > uint32Max
            || centralDirectorySize > uint32Max
            || finalRecords.contains(where: needsZip64CentralFields)

        if needsZip64 {
            var footer = BinaryWriter()
            let zip64EOCDOffset = outputOffset
            appendZip64EndOfCentralDirectory(
                entryCount: UInt64(finalRecords.count),
                centralDirectorySize: centralDirectorySize,
                centralDirectoryOffset: centralDirectoryOffset,
                to: &footer
            )
            appendZip64Locator(zip64EOCDOffset: zip64EOCDOffset, to: &footer)
            try appendEndOfCentralDirectory(
                entryCount: UInt64(finalRecords.count),
                centralDirectorySize: centralDirectorySize,
                centralDirectoryOffset: centralDirectoryOffset,
                forceSaturatedFields: forceZip64EndRecords,
                to: &footer
            )
            try outputHandle.write(contentsOf: footer.data)
        } else {
            var footer = BinaryWriter()
            try appendEndOfCentralDirectory(
                entryCount: UInt64(finalRecords.count),
                centralDirectorySize: centralDirectorySize,
                centralDirectoryOffset: centralDirectoryOffset,
                forceSaturatedFields: false,
                to: &footer
            )
            try outputHandle.write(contentsOf: footer.data)
        }

        try outputHandle.close()
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        try FileManager.default.moveItem(at: tempOutput, to: output)
        return finalRecords.count
    }

    private static func uniqueAdditions(_ additions: [LargePakPatchEntry]) throws -> [String: LargePakPatchEntry] {
        var byName: [String: LargePakPatchEntry] = [:]
        for addition in additions {
            if let existing = byName[addition.name] {
                guard existing.data == addition.data,
                      existing.centralExtraField == addition.centralExtraField,
                      existing.compressedPayload == addition.compressedPayload
                else {
                    throw LargePakPatcherError.conflictingAddition(addition.name)
                }
            } else {
                byName[addition.name] = addition
            }
        }
        return byName
    }

    private static func copyRange(
        inputHandle: FileHandle,
        outputHandle: FileHandle,
        start: UInt64,
        length: UInt64
    ) throws {
        try inputHandle.seek(toOffset: start)
        var remaining = length
        while remaining > 0 {
            let count = Int(min(UInt64(chunkSize), remaining))
            let chunk = inputHandle.readData(ofLength: count)
            if chunk.isEmpty {
                throw LargePakPatcherError.signatureNotFound("local record payload")
            }
            try outputHandle.write(contentsOf: chunk)
            remaining -= UInt64(chunk.count)
        }
    }

    private static func writeNewStoredEntry(
        _ addition: LargePakPatchEntry,
        offset: UInt64,
        outputHandle: FileHandle
    ) throws -> LargePakCentralEntry {
        let nameBytes = try CP437.encode(addition.name)
        guard nameBytes.count <= Int(UInt16.max) else {
            throw LargePakPatcherError.valueExceedsUInt16(field: "filename length", value: nameBytes.count)
        }
        guard addition.data.count <= Int(UInt32.max) else {
            throw LargePakPatcherError.valueExceedsUInt32(field: "entry size", value: UInt64(addition.data.count))
        }

        let crc: UInt32
        let compressedData: Data
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let compressionMethod: ZipCompressionMethod
        if let payload = addition.compressedPayload {
            crc = payload.crc32
            compressedData = payload.data
            compressedSize = UInt64(payload.data.count)
            uncompressedSize = UInt64(payload.uncompressedSize)
            compressionMethod = payload.compressionMethod
        } else {
            crc = addition.data.withUnsafeBytes { buffer in
                UInt32(zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(addition.data.count)))
            }
            compressedData = addition.data
            compressedSize = UInt64(addition.data.count)
            uncompressedSize = UInt64(addition.data.count)
            compressionMethod = .stored
        }
        guard compressedSize <= uint32Max else {
            throw LargePakPatcherError.valueExceedsUInt32(field: "compressed size", value: compressedSize)
        }
        guard uncompressedSize <= uint32Max else {
            throw LargePakPatcherError.valueExceedsUInt32(field: "uncompressed size", value: uncompressedSize)
        }
        var local = BinaryWriter()
        local.appendUInt32(ZipSignature.localFileHeader)
        local.appendUInt16(0x0014)
        local.appendUInt16(0)
        local.appendUInt16(compressionMethod.rawValue)
        local.appendUInt16(0x1800)
        local.appendUInt16(0x0021)
        local.appendUInt32(crc)
        local.appendUInt32(UInt32(compressedSize))
        local.appendUInt32(UInt32(uncompressedSize))
        local.appendUInt16(UInt16(nameBytes.count))
        local.appendUInt16(0)
        local.appendBytes(nameBytes)
        try outputHandle.write(contentsOf: local.data)
        try outputHandle.write(contentsOf: compressedData)

        return LargePakCentralEntry(
            name: addition.name,
            nameBytes: nameBytes,
            versionMadeBy: 0x0314,
            versionNeeded: 0x0014,
            generalPurposeBitFlag: 0,
            compressionMethod: compressionMethod,
            dosTime: 0x1800,
            dosDate: 0x0021,
            crc32: crc,
            compressedSize: compressedSize,
            uncompressedSize: uncompressedSize,
            localHeaderOffset: offset,
            centralExtra: addition.centralExtraField,
            centralComment: Data(),
            diskNumberStart: 0,
            internalAttributes: 0,
            externalAttributes: 0x81B60000,
            localRecordLength: UInt64(local.data.count) + compressedSize
        )
    }

    private static func readCentralDirectory(at url: URL) throws -> ParsedLargePak {
        let fileSize = try fileSize(at: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let eocd = try readEndOfCentralDirectory(handle: handle, fileSize: fileSize)
        try handle.seek(toOffset: eocd.centralDirectoryOffset)
        let centralData = handle.readData(ofLength: Int(eocd.centralDirectorySize))
        guard UInt64(centralData.count) == eocd.centralDirectorySize else {
            throw LargePakPatcherError.signatureNotFound("central directory")
        }

        var reader = BinaryReader(data: centralData)
        var entries: [LargePakCentralEntry] = []
        entries.reserveCapacity(Int(eocd.entryCount))
        for _ in 0..<eocd.entryCount {
            let signature = try reader.readUInt32()
            guard signature == ZipSignature.centralDirectoryHeader else {
                throw LargePakPatcherError.invalidSignature("central directory header")
            }
            let versionMadeBy = try reader.readUInt16()
            let versionNeeded = try reader.readUInt16()
            let flags = try reader.readUInt16()
            let methodRaw = try reader.readUInt16()
            guard let method = ZipCompressionMethod(rawValue: methodRaw) else {
                throw LargePakPatcherError.unsupportedCompressionMethod(methodRaw)
            }
            let dosTime = try reader.readUInt16()
            let dosDate = try reader.readUInt16()
            let crc32 = try reader.readUInt32()
            let compressed32 = try reader.readUInt32()
            let uncompressed32 = try reader.readUInt32()
            let nameLength = try reader.readUInt16()
            let extraLength = try reader.readUInt16()
            let commentLength = try reader.readUInt16()
            let diskNumberStart = try reader.readUInt16()
            let internalAttributes = try reader.readUInt16()
            let externalAttributes = try reader.readUInt32()
            let localOffset32 = try reader.readUInt32()
            let nameBytes = try reader.readBytes(count: Int(nameLength))
            let extraBytes = Data(try reader.readBytes(count: Int(extraLength)))
            let comment = Data(try reader.readBytes(count: Int(commentLength)))
            let zip64Values = try resolveZip64Values(
                compressed32: compressed32,
                uncompressed32: uncompressed32,
                localOffset32: localOffset32,
                extra: extraBytes
            )
            let name = try CP437.decode(nameBytes)
            entries.append(LargePakCentralEntry(
                name: name,
                nameBytes: nameBytes,
                versionMadeBy: versionMadeBy,
                versionNeeded: versionNeeded,
                generalPurposeBitFlag: flags,
                compressionMethod: method,
                dosTime: dosTime,
                dosDate: dosDate,
                crc32: crc32,
                compressedSize: zip64Values.compressedSize,
                uncompressedSize: zip64Values.uncompressedSize,
                localHeaderOffset: zip64Values.localHeaderOffset,
                centralExtra: extraBytes,
                centralComment: comment,
                diskNumberStart: diskNumberStart,
                internalAttributes: internalAttributes,
                externalAttributes: externalAttributes,
                localRecordLength: 0
            ))
        }

        return ParsedLargePak(
            entries: entries,
            centralDirectoryOffset: eocd.centralDirectoryOffset
        )
    }

    private static func readEndOfCentralDirectory(
        handle: FileHandle,
        fileSize: UInt64
    ) throws -> LargePakEOCD {
        let tailLength = Int(min(fileSize, UInt64(22 + Int(UInt16.max) + 128)))
        let tailStart = fileSize - UInt64(tailLength)
        try handle.seek(toOffset: tailStart)
        let tail = handle.readData(ofLength: tailLength)
        guard let eocdOffsetInTail = findSignature(ZipSignature.endOfCentralDirectory, in: tail) else {
            throw LargePakPatcherError.signatureNotFound("EOCD")
        }
        var reader = BinaryReader(data: tail, offset: eocdOffsetInTail)
        _ = try reader.readUInt32()
        let diskNumber = try reader.readUInt16()
        let centralDirectoryStartDisk = try reader.readUInt16()
        let entriesOnDisk32 = try reader.readUInt16()
        let totalEntries32 = try reader.readUInt16()
        let centralDirectorySize32 = try reader.readUInt32()
        let centralDirectoryOffset32 = try reader.readUInt32()
        let commentLength = try reader.readUInt16()
        try reader.skip(Int(commentLength))
        guard diskNumber == 0, centralDirectoryStartDisk == 0, entriesOnDisk32 == totalEntries32 else {
            throw LargePakPatcherError.multiDiskUnsupported
        }

        let locatorOffset = eocdOffsetInTail >= 20 ? eocdOffsetInTail - 20 : nil
        let hasZip64Locator = locatorOffset.map {
            UInt32(littleEndianBytes: tail[$0..<$0 + 4]) == ZipSignature.zip64Locator
        } ?? false
        let hasSaturatedFields = totalEntries32 == UInt16.max
            || centralDirectorySize32 == UInt32.max
            || centralDirectoryOffset32 == UInt32.max

        if hasZip64Locator || hasSaturatedFields {
            guard let locatorOffset, hasZip64Locator else {
                throw LargePakPatcherError.signatureNotFound("ZIP64 locator")
            }
            var locatorReader = BinaryReader(data: tail, offset: locatorOffset)
            _ = try locatorReader.readUInt32()
            let zip64Disk = try locatorReader.readUInt32()
            let zip64Offset = try locatorReader.readUInt64()
            let diskCount = try locatorReader.readUInt32()
            guard zip64Disk == 0, diskCount == 1 else {
                throw LargePakPatcherError.multiDiskUnsupported
            }
            try handle.seek(toOffset: zip64Offset)
            let zip64Data = handle.readData(ofLength: 56)
            var zip64Reader = BinaryReader(data: zip64Data)
            guard try zip64Reader.readUInt32() == ZipSignature.zip64EndOfCentralDirectory else {
                throw LargePakPatcherError.invalidSignature("ZIP64 EOCD")
            }
            _ = try zip64Reader.readUInt64()
            _ = try zip64Reader.readUInt16()
            _ = try zip64Reader.readUInt16()
            let disk = try zip64Reader.readUInt32()
            let cdDisk = try zip64Reader.readUInt32()
            let entriesOnDisk = try zip64Reader.readUInt64()
            let totalEntries = try zip64Reader.readUInt64()
            let centralSize = try zip64Reader.readUInt64()
            let centralOffset = try zip64Reader.readUInt64()
            guard disk == 0, cdDisk == 0, entriesOnDisk == totalEntries else {
                throw LargePakPatcherError.multiDiskUnsupported
            }
            return LargePakEOCD(
                entryCount: totalEntries,
                centralDirectorySize: centralSize,
                centralDirectoryOffset: centralOffset
            )
        }

        return LargePakEOCD(
            entryCount: UInt64(totalEntries32),
            centralDirectorySize: UInt64(centralDirectorySize32),
            centralDirectoryOffset: UInt64(centralDirectoryOffset32)
        )
    }

    private static func resolveZip64Values(
        compressed32: UInt32,
        uncompressed32: UInt32,
        localOffset32: UInt32,
        extra: Data
    ) throws -> (compressedSize: UInt64, uncompressedSize: UInt64, localHeaderOffset: UInt64) {
        var compressed = UInt64(compressed32)
        var uncompressed = UInt64(uncompressed32)
        var localOffset = UInt64(localOffset32)
        var offset = 0
        while offset + 4 <= extra.count {
            let fieldID = UInt16(extra[offset]) | (UInt16(extra[offset + 1]) << 8)
            let fieldLength = Int(UInt16(extra[offset + 2]) | (UInt16(extra[offset + 3]) << 8))
            offset += 4
            guard offset + fieldLength <= extra.count else { break }
            if fieldID == zip64ExtraFieldID {
                var reader = BinaryReader(data: extra.subdata(in: offset..<offset + fieldLength))
                if uncompressed32 == UInt32.max {
                    uncompressed = try reader.readUInt64()
                }
                if compressed32 == UInt32.max {
                    compressed = try reader.readUInt64()
                }
                if localOffset32 == UInt32.max {
                    localOffset = try reader.readUInt64()
                }
                break
            }
            offset += fieldLength
        }
        return (compressed, uncompressed, localOffset)
    }

    private static func appendCentralDirectoryHeader(
        _ record: LargePakCentralEntry,
        to writer: inout BinaryWriter
    ) throws {
        let needsZip64 = needsZip64CentralFields(record)
        let extra = try centralExtra(for: record)
        let versionNeeded = needsZip64 ? max(record.versionNeeded, UInt16(45)) : record.versionNeeded
        writer.appendUInt32(ZipSignature.centralDirectoryHeader)
        writer.appendUInt16(record.versionMadeBy)
        writer.appendUInt16(versionNeeded)
        writer.appendUInt16(record.generalPurposeBitFlag)
        writer.appendUInt16(record.compressionMethod.rawValue)
        writer.appendUInt16(record.dosTime)
        writer.appendUInt16(record.dosDate)
        writer.appendUInt32(record.crc32)
        writer.appendUInt32(record.compressedSize > uint32Max ? UInt32.max : UInt32(record.compressedSize))
        writer.appendUInt32(record.uncompressedSize > uint32Max ? UInt32.max : UInt32(record.uncompressedSize))
        writer.appendUInt16(UInt16(record.nameBytes.count))
        writer.appendUInt16(UInt16(extra.count))
        writer.appendUInt16(UInt16(record.centralComment.count))
        writer.appendUInt16(record.diskNumberStart)
        writer.appendUInt16(record.internalAttributes)
        writer.appendUInt32(record.externalAttributes)
        writer.appendUInt32(record.localHeaderOffset > uint32Max ? UInt32.max : UInt32(record.localHeaderOffset))
        writer.appendBytes(record.nameBytes)
        writer.appendData(extra)
        writer.appendData(record.centralComment)
    }

    private static func centralExtra(for record: LargePakCentralEntry) throws -> Data {
        let preserved = try nonZip64Extra(record.centralExtra)
        var zip64 = BinaryWriter()
        if record.uncompressedSize > uint32Max
            || record.compressedSize > uint32Max
            || record.localHeaderOffset > uint32Max {
            var payload = BinaryWriter()
            if record.uncompressedSize > uint32Max {
                payload.appendUInt64(record.uncompressedSize)
            }
            if record.compressedSize > uint32Max {
                payload.appendUInt64(record.compressedSize)
            }
            if record.localHeaderOffset > uint32Max {
                payload.appendUInt64(record.localHeaderOffset)
            }
            zip64.appendUInt16(zip64ExtraFieldID)
            zip64.appendUInt16(UInt16(payload.data.count))
            zip64.appendData(payload.data)
        }
        var result = Data()
        result.append(zip64.data)
        result.append(preserved)
        guard result.count <= Int(UInt16.max) else {
            throw LargePakPatcherError.valueExceedsUInt16(field: "central extra length", value: result.count)
        }
        return result
    }

    private static func nonZip64Extra(_ extra: Data) throws -> Data {
        var result = Data()
        var offset = 0
        while offset + 4 <= extra.count {
            let fieldID = UInt16(extra[offset]) | (UInt16(extra[offset + 1]) << 8)
            let fieldLength = Int(UInt16(extra[offset + 2]) | (UInt16(extra[offset + 3]) << 8))
            let fieldStart = offset
            offset += 4
            guard offset + fieldLength <= extra.count else { break }
            if fieldID != zip64ExtraFieldID {
                result.append(extra[fieldStart..<offset + fieldLength])
            }
            offset += fieldLength
        }
        return result
    }

    private static func appendZip64EndOfCentralDirectory(
        entryCount: UInt64,
        centralDirectorySize: UInt64,
        centralDirectoryOffset: UInt64,
        to writer: inout BinaryWriter
    ) {
        writer.appendUInt32(ZipSignature.zip64EndOfCentralDirectory)
        writer.appendUInt64(44)
        writer.appendUInt16(45)
        writer.appendUInt16(45)
        writer.appendUInt32(0)
        writer.appendUInt32(0)
        writer.appendUInt64(entryCount)
        writer.appendUInt64(entryCount)
        writer.appendUInt64(centralDirectorySize)
        writer.appendUInt64(centralDirectoryOffset)
    }

    private static func appendZip64Locator(zip64EOCDOffset: UInt64, to writer: inout BinaryWriter) {
        writer.appendUInt32(ZipSignature.zip64Locator)
        writer.appendUInt32(0)
        writer.appendUInt64(zip64EOCDOffset)
        writer.appendUInt32(1)
    }

    private static func appendEndOfCentralDirectory(
        entryCount: UInt64,
        centralDirectorySize: UInt64,
        centralDirectoryOffset: UInt64,
        forceSaturatedFields: Bool,
        to writer: inout BinaryWriter
    ) throws {
        writer.appendUInt32(ZipSignature.endOfCentralDirectory)
        writer.appendUInt16(0)
        writer.appendUInt16(0)
        writer.appendUInt16(forceSaturatedFields || entryCount > uint16Max ? UInt16.max : UInt16(entryCount))
        writer.appendUInt16(forceSaturatedFields || entryCount > uint16Max ? UInt16.max : UInt16(entryCount))
        writer.appendUInt32(forceSaturatedFields || centralDirectorySize > uint32Max ? UInt32.max : UInt32(centralDirectorySize))
        writer.appendUInt32(forceSaturatedFields || centralDirectoryOffset > uint32Max ? UInt32.max : UInt32(centralDirectoryOffset))
        writer.appendUInt16(0)
    }

    private static func needsZip64CentralFields(_ record: LargePakCentralEntry) -> Bool {
        record.compressedSize > uint32Max
            || record.uncompressedSize > uint32Max
            || record.localHeaderOffset > uint32Max
    }

    private static func findSignature(_ signature: UInt32, in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        var offset = data.count - 4
        while offset >= 0 {
            if UInt32(littleEndianBytes: data[offset..<offset + 4]) == signature {
                return offset
            }
            if offset == 0 { break }
            offset -= 1
        }
        return nil
    }

    private static func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return UInt64((attributes[.size] as? NSNumber)?.uint64Value ?? 0)
    }
}

private struct ParsedLargePak {
    let entries: [LargePakCentralEntry]
    let centralDirectoryOffset: UInt64
}

private struct LargePakEOCD {
    let entryCount: UInt64
    let centralDirectorySize: UInt64
    let centralDirectoryOffset: UInt64
}

private struct LargePakCentralEntry {
    let name: String
    let nameBytes: [UInt8]
    let versionMadeBy: UInt16
    var versionNeeded: UInt16
    let generalPurposeBitFlag: UInt16
    let compressionMethod: ZipCompressionMethod
    let dosTime: UInt16
    let dosDate: UInt16
    let crc32: UInt32
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    var localHeaderOffset: UInt64
    let centralExtra: Data
    let centralComment: Data
    let diskNumberStart: UInt16
    let internalAttributes: UInt16
    let externalAttributes: UInt32
    let localRecordLength: UInt64
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
