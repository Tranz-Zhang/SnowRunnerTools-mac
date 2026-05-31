import Foundation

public enum CP437Error: Error, CustomStringConvertible {
    case nonASCIIByte(UInt8)

    public var description: String {
        switch self {
        case let .nonASCIIByte(byte):
            return "Unsupported non-ASCII CP437 byte 0x\(String(byte, radix: 16, uppercase: true))"
        }
    }
}

public enum CP437 {
    public static func decode(_ bytes: [UInt8]) throws -> String {
        for byte in bytes where byte > 0x7F {
            throw CP437Error.nonASCIIByte(byte)
        }

        return String(decoding: bytes, as: Unicode.ASCII.self)
    }

    public static func encode(_ string: String) throws -> [UInt8] {
        let bytes = Array(string.utf8)
        for byte in bytes where byte > 0x7F {
            throw CP437Error.nonASCIIByte(byte)
        }
        return bytes
    }
}
