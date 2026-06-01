import Foundation

public enum LoadListError: Error, CustomStringConvertible, Equatable {
    case invalidVersionTag(UInt32)
    case invalidMarker(field: String, expected: UInt8, actual: UInt8)
    case invalidStringLength(Int32)
    case invalidPhaseTag(String)
    case invalidLoaderType(String)
    case invalidSourcePakIndex(Int32)
    case invalidManifestPath(String)
    case duplicateRecord(phase: String, path: String)
    case duplicateCaseInsensitiveRecord(phase: String, path: String)
    case missingSharedPak
    case missingSharedSoundPak
    case mismatchedRecordCount(phase: String, headerCount: Int, parsedCount: Int)
    case unsupportedNonASCIIString(String)
    case truncatedManifest
    case missingManifestEntry

    public var description: String {
        switch self {
        case let .invalidVersionTag(value):
            return "Invalid load-list version tag 0x\(String(value, radix: 16))"
        case let .invalidMarker(field, expected, actual):
            return "Invalid load-list marker for \(field): expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))"
        case let .invalidStringLength(value):
            return "Invalid load-list string length \(value)"
        case let .invalidPhaseTag(tag):
            return "Invalid load-list phase tag \(tag)"
        case let .invalidLoaderType(value):
            return "Invalid load-list loader type \(value)"
        case let .invalidSourcePakIndex(value):
            return "Invalid load-list source-pak index \(value)"
        case let .invalidManifestPath(value):
            return "Invalid load-list manifest path \(value)"
        case let .duplicateRecord(phase, path):
            return "Duplicate load-list record in phase \(phase): \(path)"
        case let .duplicateCaseInsensitiveRecord(phase, path):
            return "Duplicate case-insensitive load-list record in phase \(phase): \(path)"
        case .missingSharedPak:
            return "shared.pak fixture is required for this operation"
        case .missingSharedSoundPak:
            return "shared_sound.pak fixture is required for this operation"
        case let .mismatchedRecordCount(phase, headerCount, parsedCount):
            return "Mismatched load-list record count in phase \(phase): header=\(headerCount), parsed=\(parsedCount)"
        case let .unsupportedNonASCIIString(value):
            return "Unsupported non-ASCII load-list string: \(value)"
        case .truncatedManifest:
            return "Truncated load-list manifest"
        case .missingManifestEntry:
            return "PAK does not contain pak.load_list entry"
        }
    }
}
