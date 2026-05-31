import Foundation

public enum PakWriterError: Error, CustomStringConvertible, Equatable {
    case entryCountExceedsZip32(Int)
    case valueExceedsUInt16(field: String, value: Int)
    case valueExceedsUInt32(field: String, value: UInt64)
    case missingPakLoadList

    public var description: String {
        switch self {
        case let .entryCountExceedsZip32(count):
            return "Archive has too many entries for ZIP32: \(count)"
        case let .valueExceedsUInt16(field, value):
            return "\(field) exceeds UInt16: \(value)"
        case let .valueExceedsUInt32(field, value):
            return "\(field) exceeds UInt32: \(value)"
        case .missingPakLoadList:
            return "Pack input is missing pak.load_list"
        }
    }
}
