enum ZipSignature {
    static let localFileHeader: UInt32 = 0x04034B50
    static let centralDirectoryHeader: UInt32 = 0x02014B50
    static let endOfCentralDirectory: UInt32 = 0x06054B50
    static let zip64EndOfCentralDirectory: UInt32 = 0x06064B50
    static let zip64Locator: UInt32 = 0x07064B50
}

public enum ZipCompressionMethod: UInt16, Equatable {
    case stored = 0
    case deflated = 8
}
