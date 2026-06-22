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
    public static func writeArchive(fromDirectory directory: URL, to outputURL: URL, mixedCacheBlock: Bool) throws -> Int {
        try writeArchive(
            fromDirectory: directory,
            to: outputURL,
            rebuildLoadList: false,
            mixedCacheBlock: mixedCacheBlock,
            sharedPak: nil,
            sharedSoundPak: nil
        )
    }

    @discardableResult
    public static func writeArchive(
        fromDirectory directory: URL,
        to outputURL: URL,
        rebuildLoadList: Bool,
        mixedCacheBlock: Bool,
        sharedPak: URL?,
        sharedSoundPak: URL?
    ) throws -> Int {
        if !rebuildLoadList && !mixedCacheBlock {
            let sources = try PakDirectoryScanner.scan(rootDirectory: directory)
            return try writeArchive(fileSources: sources, to: outputURL)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnowRunnerCore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        var additionalFileSources: [PakFileSource] = []
        var excludedTopLevelDirectories: Set<String> = []

        if mixedCacheBlock {
            let cacheBlockURL = temporaryDirectory.appendingPathComponent(CacheBlockConstants.initialCacheBlockName)
            try CacheBlockWriter.writeArchive(fromDirectory: directory, to: cacheBlockURL, mixed: true)
            additionalFileSources.append(
                PakFileSource(internalName: CacheBlockConstants.initialCacheBlockName, fileURL: cacheBlockURL)
            )
            excludedTopLevelDirectories.formUnion(CacheBlockConstants.mixedTopLevelDirectories)
        }

        if rebuildLoadList {
            guard let sharedPak else { throw PakWriterError.missingSharedPak }
            guard let sharedSoundPak else { throw PakWriterError.missingSharedSoundPak }

            // Walk the unpacked directory (treated as `initial.pak`'s contents) plus the
            // two shared PAKs, classify each entry, build the manifest, and inject it as
            // an additional file source so any stale `pak.load_list` on disk is ignored.
            let manifestURL = temporaryDirectory.appendingPathComponent(LoadListConstants.manifestEntryName)
            let records = try collectLoadListRecordsFromDirectory(directory)
                + (try collectLoadListRecordsFromPak(sharedPak, sourcePak: "shared.pak"))
                + (try collectLoadListRecordsFromPak(sharedSoundPak, sourcePak: "shared_sound.pak"))
            let manifest = try LoadListBuilder.buildManifest(records: records)
            try LoadListWriter.writeManifest(manifest, to: manifestURL)
            additionalFileSources.append(
                PakFileSource(internalName: LoadListConstants.manifestEntryName, fileURL: manifestURL)
            )
        }

        let sources = try PakDirectoryScanner.scan(
            rootDirectory: directory,
            excludingTopLevelDirectories: excludedTopLevelDirectories,
            additionalFileSources: additionalFileSources
        )
        return try writeArchive(fileSources: sources, to: outputURL)
    }

    private static func collectLoadListRecordsFromDirectory(_ directory: URL) throws -> [LoadListRecord] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory.standardizedFileURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var records: [LoadListRecord] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { continue }
            let internalName = try PakPath.internalName(forFileAt: fileURL, rootDirectory: directory.standardizedFileURL)
            if let record = try LoadListClassifier.classify(.init(
                internalName: internalName,
                sourcePak: "initial.pak"
            )) {
                records.append(record)
            }
        }
        return records
    }

    private static func collectLoadListRecordsFromPak(_ pakURL: URL, sourcePak: String) throws -> [LoadListRecord] {
        let archive = try PakReader.readArchive(at: pakURL)
        var records: [LoadListRecord] = []
        for entry in archive.entries {
            if let record = try LoadListClassifier.classify(.init(
                internalName: entry.name,
                sourcePak: sourcePak
            )) {
                records.append(record)
            }
        }
        return records
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
            let localExtraField = try checkedExtraFieldBytes("local extra field", source.localExtraField)
            let centralExtraField = try checkedExtraFieldBytes("central extra field", source.centralExtraField)
            let sourcePayload = try payload(for: source)
            let record = WrittenEntry(
                name: source.internalName,
                nameBytes: nameBytes,
                localExtraField: localExtraField,
                centralExtraField: centralExtraField,
                compressionMethod: sourcePayload.compressionMethod,
                crc32: sourcePayload.crc32,
                compressedSize: try checkedUInt32("compressed size", UInt64(sourcePayload.data.count)),
                uncompressedSize: sourcePayload.uncompressedSize,
                localHeaderOffset: try checkedUInt32("local header offset", UInt64(writer.data.count))
            )

            appendLocalHeader(record, to: &writer)
            writer.appendData(sourcePayload.data)
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

    private static func payload(for source: PakFileSource) throws -> PakCompressedPayload {
        if case let .compressed(payload) = source.payload {
            return payload
        }

        let uncompressed = try source.readData()
        let method = compressionMethod(for: source.internalName)
        let data = method == .stored ? uncompressed : try PakDeflater.deflateRaw(uncompressed)
        return PakCompressedPayload(
            compressionMethod: method,
            data: data,
            crc32: crc32(for: uncompressed),
            uncompressedSize: try checkedUInt32("uncompressed size", UInt64(uncompressed.count))
        )
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

    private static func checkedExtraFieldBytes(_ field: String, _ data: Data) throws -> [UInt8] {
        _ = try checkedUInt16(field, data.count)
        return Array(data)
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
        writer.appendUInt16(UInt16(record.localExtraField.count))
        writer.appendBytes(record.nameBytes)
        writer.appendBytes(record.localExtraField)
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
        writer.appendUInt16(UInt16(record.centralExtraField.count))
        writer.appendUInt16(0)
        writer.appendUInt16(0)
        writer.appendUInt16(0)
        writer.appendUInt32(externalAttributes)
        writer.appendUInt32(record.localHeaderOffset)
        writer.appendBytes(record.nameBytes)
        writer.appendBytes(record.centralExtraField)
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
    let localExtraField: [UInt8]
    let centralExtraField: [UInt8]
    let compressionMethod: ZipCompressionMethod
    let crc32: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
}
