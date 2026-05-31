import Foundation

public enum PakPathError: Error, CustomStringConvertible, Equatable {
    case emptyName
    case directoryEntry(String)
    case absolutePath(URL)
    case invalidInternalName(String)
    case backslashInFileSystemComponent(String)
    case duplicateInternalName(String)
    case duplicateCaseInsensitiveInternalName(String)

    public var description: String {
        switch self {
        case .emptyName:
            return "PAK entry name is empty"
        case let .directoryEntry(name):
            return "PAK entry is a directory: \(name)"
        case let .absolutePath(url):
            return "Path is not inside pack root: \(url.path)"
        case let .invalidInternalName(name):
            return "Invalid internal PAK name: \(name)"
        case let .backslashInFileSystemComponent(component):
            return "Filesystem path component contains literal backslash: \(component)"
        case let .duplicateInternalName(name):
            return "Duplicate internal PAK name: \(name)"
        case let .duplicateCaseInsensitiveInternalName(name):
            return "Duplicate case-insensitive internal PAK name: \(name)"
        }
    }
}

public enum PakPath {
    public static func fileSystemRelativePath(forInternalName name: String) throws -> String {
        try validateInternalName(name)
        return name.split(separator: "\\", omittingEmptySubsequences: false).joined(separator: "/")
    }

    public static func internalName(forFileAt fileURL: URL, rootDirectory: URL) throws -> String {
        let rootComponents = rootDirectory.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents

        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else {
            throw PakPathError.absolutePath(fileURL)
        }

        let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))
        for component in relativeComponents where component.contains("\\") {
            throw PakPathError.backslashInFileSystemComponent(component)
        }

        let internalName = relativeComponents.joined(separator: "\\")
        try validateInternalName(internalName)
        return internalName
    }

    public static func validatePackInput(internalNames: [String]) throws {
        var exactNames = Set<String>()
        var lowercasedNames = Set<String>()

        for name in internalNames {
            try validateInternalName(name)

            guard exactNames.insert(name).inserted else {
                throw PakPathError.duplicateInternalName(name)
            }

            let lowercased = name.lowercased()
            guard lowercasedNames.insert(lowercased).inserted else {
                throw PakPathError.duplicateCaseInsensitiveInternalName(name)
            }
        }
    }

    private static func validateInternalName(_ name: String) throws {
        guard !name.isEmpty else {
            throw PakPathError.emptyName
        }

        guard !name.hasSuffix("\\") && !name.hasSuffix("/") else {
            throw PakPathError.directoryEntry(name)
        }

        guard !name.hasPrefix("/") && !name.contains("/") else {
            throw PakPathError.invalidInternalName(name)
        }

        let components = name.split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PakPathError.invalidInternalName(name)
        }

        _ = try CP437.encode(name)
    }
}
