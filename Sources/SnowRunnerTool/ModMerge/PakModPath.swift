import Foundation

public enum PakModPathError: Error, CustomStringConvertible, Equatable {
    case emptyName
    case directoryEntry(String)
    case absolutePath(URL)
    case invalidArchiveName(String)
    case duplicateArchiveName(String)
    case duplicateCaseInsensitiveArchiveName(String)

    public var description: String {
        switch self {
        case .emptyName:
            return "Mod PAK entry name is empty"
        case let .directoryEntry(name):
            return "Mod PAK entry is a directory: \(name)"
        case let .absolutePath(url):
            return "Path is not inside mod root: \(url.path)"
        case let .invalidArchiveName(name):
            return "Invalid mod PAK name: \(name)"
        case let .duplicateArchiveName(name):
            return "Duplicate mod PAK name: \(name)"
        case let .duplicateCaseInsensitiveArchiveName(name):
            return "Duplicate case-insensitive mod PAK name: \(name)"
        }
    }
}

public enum PakModPath {
    public static func isDirectoryEntry(_ name: String) -> Bool {
        name.hasSuffix("/") || name.hasSuffix("\\")
    }

    public static func fileSystemRelativePath(forArchiveName name: String) throws -> String {
        guard !isDirectoryEntry(name) else {
            throw PakModPathError.directoryEntry(name)
        }
        return try normalizedArchiveName(name)
    }

    public static func archiveName(forFileAt fileURL: URL, rootDirectory: URL) throws -> String {
        let root = rootDirectory.standardizedFileURL
        let file = fileURL.standardizedFileURL
        let rootComponents = root.pathComponents
        let fileComponents = file.pathComponents

        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else {
            throw PakModPathError.absolutePath(fileURL)
        }

        return try normalizedArchiveName(Array(fileComponents.dropFirst(rootComponents.count)).joined(separator: "/"))
    }

    public static func validatePackInput(archiveNames: [String]) throws {
        var exactNames = Set<String>()
        var lowercasedNames = Set<String>()

        for name in archiveNames {
            let normalized = try normalizedArchiveName(name)
            guard exactNames.insert(normalized).inserted else {
                throw PakModPathError.duplicateArchiveName(normalized)
            }
            let lowercased = normalized.lowercased()
            guard lowercasedNames.insert(lowercased).inserted else {
                throw PakModPathError.duplicateCaseInsensitiveArchiveName(normalized)
            }
        }
    }

    public static func normalizedArchiveName(_ name: String) throws -> String {
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty else {
            throw PakModPathError.emptyName
        }
        guard !normalized.hasPrefix("/") else {
            throw PakModPathError.invalidArchiveName(name)
        }
        guard !normalized.hasSuffix("/") else {
            throw PakModPathError.directoryEntry(name)
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PakModPathError.invalidArchiveName(name)
        }

        _ = try CP437.encode(normalized)
        return normalized
    }
}
