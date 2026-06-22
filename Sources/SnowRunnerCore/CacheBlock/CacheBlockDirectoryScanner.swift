import Foundation

public struct CacheBlockFileSource: Equatable {
    public let internalName: String
    public let externalPath: String
    public let fileURL: URL

    public init(internalName: String, externalPath: String, fileURL: URL) {
        self.internalName = internalName
        self.externalPath = externalPath
        self.fileURL = fileURL
    }
}

public enum CacheBlockDirectoryScanner {
    public static func scan(rootDirectory: URL, mixed: Bool = false) throws -> [CacheBlockFileSource] {
        let root = rootDirectory.standardizedFileURL
        let files = try mixed ? mixedFiles(in: root) : allFiles(in: root)
        let sources = try files.map { fileURL in
            let internalName = try CacheBlockPath.internalName(forFileAt: fileURL, rootDirectory: root)
            let externalPath = try CacheBlockPath.externalPath(forInternalName: internalName)
            return CacheBlockFileSource(internalName: internalName, externalPath: externalPath, fileURL: fileURL)
        }

        try CacheBlockPath.validateInternalNames(sources.map(\.internalName))
        return sources.sorted { left, right in
            if left.internalName != right.internalName {
                return left.internalName < right.internalName
            }
            return left.externalPath < right.externalPath
        }
    }

    private static func mixedFiles(in root: URL) throws -> [URL] {
        var files: [URL] = []
        for directoryName in CacheBlockConstants.mixedTopLevelDirectories {
            let directoryURL = root.appendingPathComponent(directoryName, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }
            files.append(contentsOf: try filesBelow(directoryURL))
        }
        return files
    }

    private static func allFiles(in root: URL) throws -> [URL] {
        let rootContents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for url in rootContents {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                throw CacheBlockError.rootFileNotAllowed(url.path)
            }
        }
        return try filesBelow(root)
    }

    private static func filesBelow(_ directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files
    }
}
