public struct CacheBlockEntry: Equatable {
    public let internalName: String
    public let externalPath: String
    public let relativeOffset: Int64
    public let size: Int32
    public let zero: Int32

    public init(internalName: String, externalPath: String, relativeOffset: Int64, size: Int32, zero: Int32) {
        self.internalName = internalName
        self.externalPath = externalPath
        self.relativeOffset = relativeOffset
        self.size = size
        self.zero = zero
    }
}
