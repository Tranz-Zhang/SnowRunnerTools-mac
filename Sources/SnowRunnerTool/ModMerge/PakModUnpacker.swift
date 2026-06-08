import Foundation

public enum PakModUnpacker {
    @discardableResult
    public static func unpack(archiveURL: URL, toDirectory outputDirectory: URL) throws -> Int {
        let archive = try PakReader.readArchive(at: archiveURL)
        let root = outputDirectory.standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)

        var count = 0
        for entry in archive.entries {
            if PakModPath.isDirectoryEntry(entry.name) {
                continue
            }

            let relativePath = try PakModPath.fileSystemRelativePath(forArchiveName: entry.name)
            let outputURL = root.appendingPathComponent(relativePath).standardizedFileURL
            guard outputURL.path.hasPrefix(root.path + "/") else {
                throw PakModPathError.absolutePath(outputURL)
            }

            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let payload = try PakReader.readUncompressedPayload(entry: entry, in: archive)
            try payload.write(to: outputURL, options: .atomic)
            count += 1
        }

        return count
    }
}
