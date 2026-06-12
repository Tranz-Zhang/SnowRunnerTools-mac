import Foundation

public enum PakWorkspaceError: Error, CustomStringConvertible, Equatable {
    case missingManifest(String)
    case unsupportedManifestVersion(Int)
    case missingInitialDirectory(String)
    case initialDirectoryAlreadyExists(String)
    case modDirectoryAlreadyExists(String)
    case duplicateModFolderName(String)
    case missingModDirectory(String)
    case missingSourceCache(String)
    case invalidCommand(String)
    case verificationFailed(name: String, issues: [VerifierIssue])

    public var description: String {
        switch self {
        case let .missingManifest(path):
            return "Not a pak workspace; missing \(path)"
        case let .unsupportedManifestVersion(version):
            return "Unsupported workspace manifest version: \(version)"
        case let .missingInitialDirectory(path):
            return "Workspace has no initial contents: \(path)"
        case let .initialDirectoryAlreadyExists(path):
            return "Workspace initial directory already exists and is not empty: \(path)"
        case let .modDirectoryAlreadyExists(path):
            return "Workspace mod directory already exists: \(path)"
        case let .duplicateModFolderName(name):
            return "Duplicate workspace mod folder name: \(name)"
        case let .missingModDirectory(path):
            return "Workspace manifest references missing mod directory: \(path)"
        case let .missingSourceCache(path):
            return "Workspace manifest references missing cached source PAK: \(path)"
        case let .invalidCommand(message):
            return message
        case let .verificationFailed(name, issues):
            let details = issues.map { "\($0.code): \($0.message)" }.joined(separator: "\n")
            return "\(name) failed:\n\(details)"
        }
    }
}
