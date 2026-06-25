import Foundation

public enum ModMergeError: Error, CustomStringConvertible, Equatable {
    case unsupportedModPath(archive: String, path: String)
    case invalidModArchive(archive: String, reason: String)
    case invalidStringTable(path: String, reason: String)
    case invalidCustomizationPreset(path: String, reason: String)
    case invalidRegistryXML(path: String, reason: String)
    case brokenMergedReferences([ModReferenceIssue])
    case overwriteRequired(paths: [String])
    case conflictingMappedDuplicate(path: String)
    case outputPathMatchesInput(String)
    case missingBaseManifest
    case missingTextureOutput
    case missingSharedTextureOutput
    case verificationFailed(name: String, issues: [VerifierIssue])

    public var description: String {
        switch self {
        case let .unsupportedModPath(archive, path):
            return "Unsupported mod path in \(archive): \(path)"
        case let .invalidModArchive(archive, reason):
            return "Invalid mod archive \(archive): \(reason)"
        case let .invalidStringTable(path, reason):
            return "Invalid string table \(path): \(reason)"
        case let .invalidCustomizationPreset(path, reason):
            return "Invalid customization preset \(path): \(reason)"
        case let .invalidRegistryXML(path, reason):
            return "Invalid registry XML \(path): \(reason)"
        case let .brokenMergedReferences(issues):
            let details = issues.prefix(25).map {
                "\($0.sourcePath): missing \($0.referencedCategory) '\($0.missingValue)' - \($0.explanation)"
            }.joined(separator: "\n")
            return "Merged initial.pak has unresolved references:\n\(details)"
        case let .overwriteRequired(paths):
            let examples = paths.prefix(10).joined(separator: "\n")
            return "Mapped mod entries collide with existing base entries. Re-run with --allow-overwrite to replace them:\n\(examples)"
        case let .conflictingMappedDuplicate(path):
            return "Two mod entries map to \(path) with different decompressed bytes"
        case let .outputPathMatchesInput(path):
            return "Output path must be distinct from every input PAK: \(path)"
        case .missingBaseManifest:
            return "Base initial.pak does not contain pak.load_list"
        case .missingTextureOutput:
            return "Texture merge requires --input-textures and --output-textures"
        case .missingSharedTextureOutput:
            return "PCT texture merge requires --input-shared-textures and --output-shared-textures"
        case let .verificationFailed(name, issues):
            let details = issues.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
            return "\(name) failed:\n\(details)"
        }
    }
}
