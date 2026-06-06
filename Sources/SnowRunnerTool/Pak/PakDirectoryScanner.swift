import Foundation

public struct PakFileSource: Equatable {
    public let internalName: String
    public let payload: PakSourcePayload
    public let localExtraField: Data
    public let centralExtraField: Data

    public init(internalName: String, fileURL: URL) {
        self.internalName = internalName
        self.payload = .fileURL(fileURL)
        self.localExtraField = Data()
        self.centralExtraField = Data()
    }

    public init(
        internalName: String,
        data: Data,
        localExtraField: Data = Data(),
        centralExtraField: Data = Data()
    ) {
        self.internalName = internalName
        self.payload = .data(data)
        self.localExtraField = localExtraField
        self.centralExtraField = centralExtraField
    }

    public init(
        internalName: String,
        compressedPayload: PakCompressedPayload,
        localExtraField: Data = Data(),
        centralExtraField: Data = Data()
    ) {
        self.internalName = internalName
        self.payload = .compressed(compressedPayload)
        self.localExtraField = localExtraField
        self.centralExtraField = centralExtraField
    }

    public var fileURL: URL? {
        guard case let .fileURL(url) = payload else { return nil }
        return url
    }

    public func readData() throws -> Data {
        switch payload {
        case let .fileURL(url):
            return try Data(contentsOf: url)
        case let .data(data):
            return data
        case let .compressed(payload):
            switch payload.compressionMethod {
            case .stored:
                return payload.data
            case .deflated:
                return try PakInflater.inflateRawDeflate(payload.data, expectedSize: payload.uncompressedSize)
            }
        }
    }
}

public enum PakSourcePayload: Equatable {
    case fileURL(URL)
    case data(Data)
    case compressed(PakCompressedPayload)
}

public struct PakCompressedPayload: Equatable {
    public let compressionMethod: ZipCompressionMethod
    public let data: Data
    public let crc32: UInt32
    public let uncompressedSize: UInt32

    public init(
        compressionMethod: ZipCompressionMethod,
        data: Data,
        crc32: UInt32,
        uncompressedSize: UInt32
    ) {
        self.compressionMethod = compressionMethod
        self.data = data
        self.crc32 = crc32
        self.uncompressedSize = uncompressedSize
    }
}

public struct PakSortKey: Equatable {
    public let bucket: Int
    public let lowercased: String

    public init(bucket: Int, lowercased: String) {
        self.bucket = bucket
        self.lowercased = lowercased
    }
}

public enum PakDirectoryScanner {
    public static func scan(rootDirectory: URL) throws -> [PakFileSource] {
        try scan(rootDirectory: rootDirectory, excludingTopLevelDirectories: [], additionalFileSources: [])
    }

    public static func scan(
        rootDirectory: URL,
        excludingTopLevelDirectories excludedDirectories: Set<String>,
        additionalFileSources: [PakFileSource]
    ) throws -> [PakFileSource] {
        let root = rootDirectory.standardizedFileURL
        let additionalNames = Set(additionalFileSources.map(\.internalName))
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            throw PakWriterError.missingPakLoadList
        }

        var sources: [PakFileSource] = []
        for case let fileURL as URL in enumerator {
            let relativeComponents = Array(fileURL.standardizedFileURL.pathComponents.dropFirst(root.pathComponents.count))
            if let topLevel = relativeComponents.first, excludedDirectories.contains(topLevel) {
                enumerator.skipDescendants()
                continue
            }

            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else {
                continue
            }

            let internalName = try PakPath.internalName(forFileAt: fileURL, rootDirectory: root)
            if additionalNames.contains(internalName) {
                continue
            }
            sources.append(PakFileSource(internalName: internalName, fileURL: fileURL))
        }

        return try sortedPackSources(sources + additionalFileSources, requirePakLoadList: true)
    }

    public static func sortedPackSources(
        _ sources: [PakFileSource],
        requirePakLoadList: Bool = true
    ) throws -> [PakFileSource] {
        try PakPath.validatePackInput(internalNames: sources.map(\.internalName))
        if requirePakLoadList && !sources.contains(where: { $0.internalName == "pak.load_list" }) {
            throw PakWriterError.missingPakLoadList
        }

        return sources.sorted { left, right in
            let leftKey = writerSortKey(left.internalName)
            let rightKey = writerSortKey(right.internalName)
            if leftKey.bucket != rightKey.bucket {
                return leftKey.bucket < rightKey.bucket
            }
            if leftKey.lowercased != rightKey.lowercased {
                return leftKey.lowercased < rightKey.lowercased
            }
            return left.internalName < right.internalName
        }
    }

    public static func writerSortKey(_ name: String) -> PakSortKey {
        if name == "pak.load_list" {
            return PakSortKey(bucket: 0, lowercased: "")
        }
        if name == "initial.cache_block" {
            return PakSortKey(bucket: 1, lowercased: "")
        }
        if name.hasPrefix("[media]\\classes") {
            return PakSortKey(bucket: 2, lowercased: name.lowercased())
        }
        if name.hasPrefix("[media]\\_dlc") {
            return PakSortKey(bucket: 3, lowercased: name.lowercased())
        }
        if name.hasPrefix("[media]\\_templates") {
            return PakSortKey(bucket: 4, lowercased: name.lowercased())
        }
        if name.hasPrefix("[ssl_cache]") {
            return PakSortKey(bucket: 5, lowercased: name.lowercased())
        }
        if name.hasPrefix("[strings]") {
            return PakSortKey(bucket: 6, lowercased: name.lowercased())
        }
        if name.hasPrefix("[meshes]") {
            return PakSortKey(bucket: 7, lowercased: name.lowercased())
        }
        if name.hasPrefix("[textures]") {
            return PakSortKey(bucket: 8, lowercased: name.lowercased())
        }
        if name.hasPrefix("[ui]") {
            return PakSortKey(bucket: 9, lowercased: name.lowercased())
        }
        return PakSortKey(bucket: 10, lowercased: name.lowercased())
    }
}
