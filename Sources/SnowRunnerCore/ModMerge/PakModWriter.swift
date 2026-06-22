import Foundation

public enum PakModWriter {
    @discardableResult
    public static func writeArchive(fromDirectory directory: URL, to outputURL: URL) throws -> Int {
        let sources = try PakModDirectoryScanner.scan(rootDirectory: directory)
        try validateMergeCompatibility(sources: sources, archiveName: outputURL.lastPathComponent)
        return try PakWriter.writeArchive(fileSources: sources, to: outputURL)
    }

    private static func validateMergeCompatibility(sources: [PakFileSource], archiveName: String) throws {
        try ModArchiveMapper.validateMergeCompatiblePackagePaths(
            sources.map(\.internalName),
            archiveName: archiveName
        )

        for source in sources where source.internalName.hasPrefix("prebuild/textures/") {
            guard source.internalName.hasSuffix(".pct") else {
                throw ModMergeError.unsupportedModPath(archive: archiveName, path: source.internalName)
            }
            do {
                _ = try PCTHeaderGenerator.headerData(for: source.readData())
            } catch {
                throw ModMergeError.invalidModArchive(
                    archive: archiveName,
                    reason: "\(source.internalName) invalid PCT texture: \(error)"
                )
            }
        }
    }
}

public enum PakModDirectoryScanner {
    public static func scan(rootDirectory: URL) throws -> [PakFileSource] {
        let root = rootDirectory.standardizedFileURL
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [PakFileSource] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else {
                continue
            }

            let archiveName = try PakModPath.archiveName(forFileAt: fileURL, rootDirectory: root)
            sources.append(PakFileSource(internalName: archiveName, fileURL: fileURL))
        }

        try PakModPath.validatePackInput(archiveNames: sources.map(\.internalName))
        return sources.sorted {
            if $0.internalName.lowercased() != $1.internalName.lowercased() {
                return $0.internalName.lowercased() < $1.internalName.lowercased()
            }
            return $0.internalName < $1.internalName
        }
    }
}
