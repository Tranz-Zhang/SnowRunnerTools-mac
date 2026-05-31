import Foundation

public enum CacheBlockError: Error, CustomStringConvertible, Equatable {
    case invalidHeader
    case invalidMarker(field: String, expected: String, actual: String)
    case invalidEntryCount(Int32)
    case invalidStringLength(Int32)
    case invalidInternalName(String)
    case invalidExternalPath(String)
    case duplicateInternalName(String)
    case duplicateCaseInsensitiveInternalName(String)
    case valueExceedsInt32(field: String, value: UInt64)
    case negativeOffset(entry: String, offset: Int64)
    case negativeSize(entry: String, size: Int32)
    case payloadOutOfBounds(entry: String)
    case rootFileNotAllowed(String)
    case missingInitialCacheBlock
    case outputAlreadyExists(String)

    public var description: String {
        switch self {
        case .invalidHeader:
            return "Invalid cache_block header"
        case let .invalidMarker(field, expected, actual):
            return "Invalid cache_block \(field): expected \(expected), got \(actual)"
        case let .invalidEntryCount(count):
            return "Invalid cache_block entry count: \(count)"
        case let .invalidStringLength(length):
            return "Invalid cache_block string length: \(length)"
        case let .invalidInternalName(name):
            return "Invalid cache_block internal name: \(name)"
        case let .invalidExternalPath(path):
            return "Invalid cache_block external path: \(path)"
        case let .duplicateInternalName(name):
            return "Duplicate cache_block internal name: \(name)"
        case let .duplicateCaseInsensitiveInternalName(name):
            return "Duplicate case-insensitive cache_block internal name: \(name)"
        case let .valueExceedsInt32(field, value):
            return "\(field) exceeds Int32: \(value)"
        case let .negativeOffset(entry, offset):
            return "\(entry) has negative cache_block offset: \(offset)"
        case let .negativeSize(entry, size):
            return "\(entry) has negative cache_block size: \(size)"
        case let .payloadOutOfBounds(entry):
            return "Cache_block payload is out of bounds for \(entry)"
        case let .rootFileNotAllowed(path):
            return "Cache_block source has a root file: \(path)"
        case .missingInitialCacheBlock:
            return "Missing initial.cache_block"
        case let .outputAlreadyExists(path):
            return "Cache_block output already exists: \(path)"
        }
    }
}
