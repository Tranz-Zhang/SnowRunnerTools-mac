import Foundation

public struct PakFileSource: Equatable {
    public let internalName: String
    public let fileURL: URL

    public init(internalName: String, fileURL: URL) {
        self.internalName = internalName
        self.fileURL = fileURL
    }
}

public enum PakDirectoryScanner {
    public static func scan(rootDirectory: URL) throws -> [PakFileSource] {
        let root = rootDirectory.standardizedFileURL
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
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else {
                continue
            }

            let internalName = try PakPath.internalName(forFileAt: fileURL, rootDirectory: root)
            sources.append(PakFileSource(internalName: internalName, fileURL: fileURL))
        }

        try PakPath.validatePackInput(internalNames: sources.map(\.internalName))
        guard sources.contains(where: { $0.internalName == "pak.load_list" }) else {
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

    private static func writerSortKey(_ name: String) -> (bucket: Int, lowercased: String) {
        if name == "pak.load_list" {
            return (0, "")
        }
        if name == "initial.cache_block" {
            return (1, "")
        }
        if name.hasPrefix("[media]\\classes") {
            return (2, name.lowercased())
        }
        if name.hasPrefix("[media]\\_dlc") {
            return (3, name.lowercased())
        }
        if name.hasPrefix("[media]\\_templates") {
            return (4, name.lowercased())
        }
        if name.hasPrefix("[ssl_cache]") {
            return (5, name.lowercased())
        }
        if name.hasPrefix("[strings]") {
            return (6, name.lowercased())
        }
        return (7, name.lowercased())
    }
}
