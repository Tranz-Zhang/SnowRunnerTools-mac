import Foundation

public struct CacheBlockArchive {
    public let url: URL?
    public let data: Data
    public let entries: [CacheBlockEntry]
    public let baseOffset: Int

    public init(url: URL?, data: Data, entries: [CacheBlockEntry], baseOffset: Int) {
        self.url = url
        self.data = data
        self.entries = entries
        self.baseOffset = baseOffset
    }
}
