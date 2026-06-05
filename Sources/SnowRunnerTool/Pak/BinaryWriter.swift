import Foundation

public struct BinaryWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func appendUInt8(_ value: UInt8) {
        data.append(value)
    }

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

    public mutating func appendInt32(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }

    public mutating func appendInt64(_ value: Int64) {
        let raw = UInt64(bitPattern: value)
        data.append(UInt8(raw & 0x00000000000000FF))
        data.append(UInt8((raw >> 8) & 0x00000000000000FF))
        data.append(UInt8((raw >> 16) & 0x00000000000000FF))
        data.append(UInt8((raw >> 24) & 0x00000000000000FF))
        data.append(UInt8((raw >> 32) & 0x00000000000000FF))
        data.append(UInt8((raw >> 40) & 0x00000000000000FF))
        data.append(UInt8((raw >> 48) & 0x00000000000000FF))
        data.append(UInt8((raw >> 56) & 0x00000000000000FF))
    }

    public mutating func appendUInt64(_ value: UInt64) {
        appendInt64(Int64(bitPattern: value))
    }

    public mutating func appendBytes(_ bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    public mutating func appendData(_ payload: Data) {
        data.append(payload)
    }
}
