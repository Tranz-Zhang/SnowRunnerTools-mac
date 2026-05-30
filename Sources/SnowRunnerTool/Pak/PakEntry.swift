import Foundation

public struct PakEntry: Equatable {
    public let name: String
    public let compressionMethod: ZipCompressionMethod
    public let generalPurposeBitFlag: UInt16
    public let crc32: UInt32
    public let compressedSize: UInt32
    public let uncompressedSize: UInt32
    public let versionNeeded: UInt16
    public let dosTime: UInt16
    public let dosDate: UInt16
    public let localHeaderOffset: UInt32
    public let dataOffset: Int
    public let localExtraFieldLength: UInt16
    public let centralVersionMadeBy: UInt16?
    public let centralExtraFieldLength: UInt16?
    public let centralFileCommentLength: UInt16?
    public let centralExternalAttributes: UInt32?

    public init(
        name: String,
        compressionMethod: ZipCompressionMethod,
        generalPurposeBitFlag: UInt16,
        crc32: UInt32,
        compressedSize: UInt32,
        uncompressedSize: UInt32,
        versionNeeded: UInt16,
        dosTime: UInt16,
        dosDate: UInt16,
        localHeaderOffset: UInt32,
        dataOffset: Int,
        localExtraFieldLength: UInt16,
        centralVersionMadeBy: UInt16?,
        centralExtraFieldLength: UInt16?,
        centralFileCommentLength: UInt16?,
        centralExternalAttributes: UInt32?
    ) {
        self.name = name
        self.compressionMethod = compressionMethod
        self.generalPurposeBitFlag = generalPurposeBitFlag
        self.crc32 = crc32
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.versionNeeded = versionNeeded
        self.dosTime = dosTime
        self.dosDate = dosDate
        self.localHeaderOffset = localHeaderOffset
        self.dataOffset = dataOffset
        self.localExtraFieldLength = localExtraFieldLength
        self.centralVersionMadeBy = centralVersionMadeBy
        self.centralExtraFieldLength = centralExtraFieldLength
        self.centralFileCommentLength = centralFileCommentLength
        self.centralExternalAttributes = centralExternalAttributes
    }
}
