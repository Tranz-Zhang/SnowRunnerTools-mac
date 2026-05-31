import Foundation

public enum CacheBlockUnpacker {
    @discardableResult
    public static func unpack(cacheBlockURL: URL, toDirectory outputDirectory: URL) throws -> Int {
        let archive = try CacheBlockReader.readArchive(at: cacheBlockURL)

        for entry in archive.entries {
            let outputURL = outputDirectory.appendingPathComponent(entry.externalPath)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                throw CacheBlockError.outputAlreadyExists(outputURL.path)
            }

            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try CacheBlockReader.readPayload(entry: entry, in: archive).write(to: outputURL)
        }

        return archive.entries.count
    }
}
