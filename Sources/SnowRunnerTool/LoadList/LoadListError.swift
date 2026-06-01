import Foundation

public enum LoadListError: Error, CustomStringConvertible, Equatable {
    case invalidVersionTag(UInt32)
    case invalidMarker(field: String, expected: UInt8, actual: UInt8)
    case invalidStringLength(Int32)
    case invalidEntryType(UInt8)
    case invalidStartEntry
    case invalidEndEntry
    case invalidEntryStringsCount(kind: String, count: Int)
    case invalidMagicByte(field: String, expected: UInt8, actual: UInt8)
    case invalidMagicBCount(Int)
    case invalidPhaseTag(String)
    case invalidLoaderType(String)
    case invalidSourcePakIndex(Int32)
    case invalidManifestPath(String)
    case invalidDependencyIndex(entry: Int, dependency: Int32)
    case duplicateRecord(phase: String, path: String)
    case duplicateCaseInsensitiveRecord(phase: String, path: String)
    case missingSharedPak
    case missingSharedSoundPak
    case mismatchedRecordCount(phase: String, headerCount: Int, parsedCount: Int)
    case unsupportedNonASCIIString(String)
    case truncatedManifest
    case missingManifestEntry
    case trailingBytes(Int)

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
        case let .invalidEntryType(value):
            return "Invalid load-list entry type 0x\(String(value, radix: 16))"
        case .invalidStartEntry:
            return "Load-list does not begin with a Start entry"
        case .invalidEndEntry:
            return "Load-list does not end with an End entry"
        case let .invalidEntryStringsCount(kind, count):
            return "Invalid load-list strings count \(count) for entry kind \(kind)"
        case let .invalidMagicByte(field, expected, actual):
            return "Invalid load-list magic byte for \(field): expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))"
        case let .invalidMagicBCount(value):
            return "Invalid load-list magicB count \(value)"
        case let .invalidDependencyIndex(entry, dependency):
            return "Invalid load-list dependency index \(dependency) for entry \(entry)"
        case let .trailingBytes(count):
            return "Load-list manifest has \(count) trailing bytes"
        }
    }
}
