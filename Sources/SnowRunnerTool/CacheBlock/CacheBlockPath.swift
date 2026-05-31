import Foundation

public enum CacheBlockPath {
    public static func externalPath(forInternalName name: String) throws -> String {
        let parsed = try parseInternalName(name)
        if parsed.directoryComponents.isEmpty {
            return "[\(parsed.namespace)]/\(parsed.filename)"
        }
        return ([ "[\(parsed.namespace)]" ] + parsed.directoryComponents + [parsed.filename]).joined(separator: "/")
    }

    public static func internalName(forExternalPath path: String) throws -> String {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            throw CacheBlockError.invalidExternalPath(path)
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2,
              let first = components.first,
              first.hasPrefix("["),
              first.hasSuffix("]"),
              first.count > 2
        else {
            throw CacheBlockError.invalidExternalPath(path)
        }

        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CacheBlockError.invalidExternalPath(path)
        }

        for component in components where component.contains("\\") {
            throw CacheBlockError.invalidExternalPath(path)
        }

        let namespace = String(first.dropFirst().dropLast())
        guard !namespace.isEmpty else {
            throw CacheBlockError.invalidExternalPath(path)
        }

        let tail = Array(components.dropFirst())
        let filename = tail.last ?? ""
        _ = try CP437.encode(path)

        if tail.count == 1 {
            return "<\(namespace)>:\(filename)"
        }

        let directories = tail.dropLast().joined(separator: "\\")
        return "<\(namespace)>\\\(directories)\\\(filename)"
    }

    public static func internalName(forFileAt fileURL: URL, rootDirectory: URL) throws -> String {
        let rootComponents = rootDirectory.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents

        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else {
            throw CacheBlockError.invalidExternalPath(fileURL.path)
        }

        let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))
        for component in relativeComponents where component.contains("\\") {
            throw CacheBlockError.invalidExternalPath(fileURL.path)
        }

        return try internalName(forExternalPath: relativeComponents.joined(separator: "/"))
    }

    public static func validateInternalNames(_ names: [String]) throws {
        var exactNames = Set<String>()
        var lowercasedNames = Set<String>()

        for name in names {
            _ = try parseInternalName(name)

            guard exactNames.insert(name).inserted else {
                throw CacheBlockError.duplicateInternalName(name)
            }

            let lowercased = name.lowercased()
            guard lowercasedNames.insert(lowercased).inserted else {
                throw CacheBlockError.duplicateCaseInsensitiveInternalName(name)
            }
        }
    }

    private static func parseInternalName(_ name: String) throws -> (namespace: String, directoryComponents: [String], filename: String) {
        guard name.hasPrefix("<"), let namespaceEnd = name.firstIndex(of: ">") else {
            throw CacheBlockError.invalidInternalName(name)
        }

        let namespace = String(name[name.index(after: name.startIndex)..<namespaceEnd])
        guard !namespace.isEmpty else {
            throw CacheBlockError.invalidInternalName(name)
        }

        let remainder = String(name[name.index(after: namespaceEnd)...])
        guard !remainder.isEmpty else {
            throw CacheBlockError.invalidInternalName(name)
        }

        let filename: String
        let directoryComponents: [String]
        if remainder.hasPrefix(":") {
            filename = String(remainder.dropFirst())
            directoryComponents = []
        } else if remainder.hasPrefix("\\") {
            let tail = String(remainder.dropFirst())
            let components = tail.split(separator: "\\", omittingEmptySubsequences: false).map(String.init)
            guard components.count >= 2 else {
                throw CacheBlockError.invalidInternalName(name)
            }
            filename = components.last ?? ""
            directoryComponents = Array(components.dropLast())
        } else {
            throw CacheBlockError.invalidInternalName(name)
        }

        guard !filename.isEmpty else {
            throw CacheBlockError.invalidInternalName(name)
        }

        let components = directoryComponents + [filename]
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CacheBlockError.invalidInternalName(name)
        }

        _ = try CP437.encode(name)
        return (namespace, directoryComponents, filename)
    }
}
