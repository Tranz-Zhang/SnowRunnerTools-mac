import Foundation

public struct PakArchive {
    public let url: URL
    public let data: Data
    public let entries: [PakEntry]
    public let localEntries: [PakEntry]
    public let centralDirectoryOffset: UInt32
    public let centralDirectorySize: UInt32
    public let archiveCommentLength: UInt16
    public let isZip64: Bool

    public init(
        url: URL,
        data: Data,
        entries: [PakEntry],
        localEntries: [PakEntry],
        centralDirectoryOffset: UInt32,
        centralDirectorySize: UInt32,
        archiveCommentLength: UInt16,
        isZip64: Bool
    ) {
        self.url = url
        self.data = data
        self.entries = entries
        self.localEntries = localEntries
        self.centralDirectoryOffset = centralDirectoryOffset
        self.centralDirectorySize = centralDirectorySize
        self.archiveCommentLength = archiveCommentLength
        self.isZip64 = isZip64
    }
}
