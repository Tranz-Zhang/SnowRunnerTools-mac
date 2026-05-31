import Foundation

public enum PakUnpacker {
    @discardableResult
    public static func unpack(archiveURL: URL, toDirectory outputDirectory: URL) throws -> Int {
        let archive = try PakReader.readArchive(at: archiveURL)
        let root = outputDirectory.standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)

        for entry in archive.entries {
            let relativePath = try PakPath.fileSystemRelativePath(forInternalName: entry.name)
            let outputURL = root.appendingPathComponent(relativePath).standardizedFileURL
            guard outputURL.path.hasPrefix(root.path + "/") || outputURL == root else {
                throw PakPathError.absolutePath(outputURL)
            }

            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let payload = try PakReader.readUncompressedPayload(entry: entry, in: archive)
            try payload.write(to: outputURL, options: .atomic)
        }

        return archive.entries.count
    }
}
