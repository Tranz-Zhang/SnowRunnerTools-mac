import Foundation

public enum PCTHeaderError: Error, CustomStringConvertible, Equatable {
    case tooShort
    case invalidMagic
    case invalidHeaderLength(Int)

    public var description: String {
        switch self {
        case .tooShort:
            return "PCT payload is shorter than the fixed header"
        case .invalidMagic:
            return "PCT payload does not contain TCIP magic"
        case let .invalidHeaderLength(length):
            return "PCT header length is invalid: \(length)"
        }
    }
}

public enum PCTHeaderGenerator {
    public static func headerData(for pctData: Data) throws -> Data {
        guard pctData.count >= 64 else {
            throw PCTHeaderError.tooShort
        }
        guard pctData[6] == UInt8(ascii: "T"),
              pctData[7] == UInt8(ascii: "C"),
              pctData[8] == UInt8(ascii: "I"),
              pctData[9] == UInt8(ascii: "P")
        else {
            throw PCTHeaderError.invalidMagic
        }

        let tableCount = UInt32(pctData[48])
            | (UInt32(pctData[49]) << 8)
            | (UInt32(pctData[50]) << 16)
            | (UInt32(pctData[51]) << 24)
        let headerLength64 = 64 + UInt64(tableCount) * 8
        guard headerLength64 <= UInt64(Int.max) else {
            throw PCTHeaderError.invalidHeaderLength(Int.max)
        }
        let headerLength = Int(headerLength64)
        guard headerLength >= 64, headerLength <= pctData.count else {
            throw PCTHeaderError.invalidHeaderLength(headerLength)
        }

        var header = pctData.prefix(headerLength)
        header[headerLength - 6] = 0x01
        header[headerLength - 4] = UInt8(headerLength & 0xFF)
        header[headerLength - 3] = UInt8((headerLength >> 8) & 0xFF)
        header[headerLength - 2] = UInt8((headerLength >> 16) & 0xFF)
        header[headerLength - 1] = UInt8((headerLength >> 24) & 0xFF)
        return Data(header)
    }
}
