import Foundation

public enum BinaryReaderError: Error, CustomStringConvertible {
    case unexpectedEnd(offset: Int, requested: Int, available: Int)
    case invalidOffset(Int)

    public var description: String {
        switch self {
        case let .unexpectedEnd(offset, requested, available):
            return "Unexpected end of data at offset \(offset); requested \(requested) bytes, available \(available)"
        case let .invalidOffset(offset):
            return "Invalid offset \(offset)"
        }
    }
}

public struct BinaryReader {
    private let data: Data
    public private(set) var offset: Int

    public init(data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    public mutating func readUInt16() throws -> UInt16 {
        let bytes = try readBytes(count: 2)
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    public mutating func readUInt32() throws -> UInt32 {
        let bytes = try readBytes(count: 4)
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }

    public mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0 else {
            throw BinaryReaderError.invalidOffset(count)
        }
        guard offset <= data.count, data.count - offset >= count else {
            throw BinaryReaderError.unexpectedEnd(offset: offset, requested: count, available: max(0, data.count - offset))
        }

        let start = offset
        offset += count
        return Array(data[start..<offset])
    }

    public mutating func seek(to newOffset: Int) throws {
        guard (0...data.count).contains(newOffset) else {
            throw BinaryReaderError.invalidOffset(newOffset)
        }
        offset = newOffset
    }

    public mutating func skip(_ count: Int) throws {
        try seek(to: offset + count)
    }
}
