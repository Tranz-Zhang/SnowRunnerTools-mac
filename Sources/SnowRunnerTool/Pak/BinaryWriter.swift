import Foundation

public struct BinaryWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func appendUInt16(_ value: UInt16) {
        data.append(UInt8(value & 0x00FF))
        data.append(UInt8((value >> 8) & 0x00FF))
    }

    public mutating func appendUInt32(_ value: UInt32) {
        data.append(UInt8(value & 0x000000FF))
        data.append(UInt8((value >> 8) & 0x000000FF))
        data.append(UInt8((value >> 16) & 0x000000FF))
        data.append(UInt8((value >> 24) & 0x000000FF))
    }

    public mutating func appendBytes(_ bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    public mutating func appendData(_ payload: Data) {
        data.append(payload)
    }
}
