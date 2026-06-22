import Foundation

public struct PakWorkspaceManifest: Codable, Equatable {
    public let version: Int
    public var initialSourcePath: String
    public var mods: [PakWorkspaceMod]
    public var policy: PakWorkspacePolicy

    public init(version: Int, initialSourcePath: String, mods: [PakWorkspaceMod], policy: PakWorkspacePolicy) {
        self.version = version
        self.initialSourcePath = initialSourcePath
        self.mods = mods
        self.policy = policy
    }
}

public struct PakWorkspaceMod: Codable, Equatable {
    public var sourcePath: String
    public var folderName: String
    public var archiveName: String
    public var sourceCachePath: String
    public var enabled: Bool
    public var entries: [PakWorkspaceSourceEntry]

    private enum CodingKeys: String, CodingKey {
        case sourcePath
        case folderName
        case archiveName
        case sourceCachePath
        case enabled
        case entries
    }

    public init(
        sourcePath: String,
        folderName: String,
        archiveName: String,
        sourceCachePath: String,
        enabled: Bool = true,
        entries: [PakWorkspaceSourceEntry]
    ) {
        self.sourcePath = sourcePath
        self.folderName = folderName
        self.archiveName = archiveName
        self.sourceCachePath = sourceCachePath
        self.enabled = enabled
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        folderName = try container.decode(String.self, forKey: .folderName)
        archiveName = try container.decode(String.self, forKey: .archiveName)
        sourceCachePath = try container.decode(String.self, forKey: .sourceCachePath)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        entries = try container.decode([PakWorkspaceSourceEntry].self, forKey: .entries)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(folderName, forKey: .folderName)
        try container.encode(archiveName, forKey: .archiveName)
        try container.encode(sourceCachePath, forKey: .sourceCachePath)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(entries, forKey: .entries)
    }
}

public struct PakWorkspaceSourceEntry: Codable, Equatable {
    public var sourceEntryName: String
    public var workspacePath: String
    public var sha256: String

    public init(sourceEntryName: String, workspacePath: String, sha256: String) {
        self.sourceEntryName = sourceEntryName
        self.workspacePath = workspacePath
        self.sha256 = sha256
    }
}

public struct PakWorkspacePolicy: Codable, Equatable {
    public var textureMode: String
    public var allowInitialOverwrite: Bool

    public init(textureMode: String, allowInitialOverwrite: Bool) {
        self.textureMode = textureMode
        self.allowInitialOverwrite = allowInitialOverwrite
    }
}

public enum PakWorkspacePaths {
    public static let manifestName = ".snowrunner-workspace.json"
    public static let initialDirectoryName = "initial"
    public static let modsDirectoryName = "mods"
    public static let metadataDirectoryName = ".snowrunner"
    public static let sourcesDirectoryName = "sources"
    public static let buildDirectoryName = "build"
    public static let buildReportName = "workspace-build-report.md"

    public static func manifestURL(root: URL) -> URL {
        root.appendingPathComponent(manifestName)
    }

    public static func initialDirectory(root: URL) -> URL {
        root.appendingPathComponent(initialDirectoryName, isDirectory: true)
    }

    public static func modsDirectory(root: URL) -> URL {
        root.appendingPathComponent(modsDirectoryName, isDirectory: true)
    }

    public static func modDirectory(root: URL, folderName: String) -> URL {
        modsDirectory(root: root).appendingPathComponent(folderName, isDirectory: true)
    }

    public static func metadataDirectory(root: URL) -> URL {
        root.appendingPathComponent(metadataDirectoryName, isDirectory: true)
    }

    public static func sourcesDirectory(root: URL) -> URL {
        metadataDirectory(root: root).appendingPathComponent(sourcesDirectoryName, isDirectory: true)
    }

    public static func sourceCache(root: URL, folderName: String) -> URL {
        sourcesDirectory(root: root).appendingPathComponent(folderName + ".pak")
    }

    public static func buildDirectory(root: URL) -> URL {
        root.appendingPathComponent(buildDirectoryName, isDirectory: true)
    }

    public static func buildInitialPak(root: URL) -> URL {
        buildDirectory(root: root).appendingPathComponent("initial.pak")
    }

    public static func buildReport(root: URL) -> URL {
        buildDirectory(root: root).appendingPathComponent(buildReportName)
    }
}

public extension JSONEncoder {
    static var pakWorkspace: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var pakWorkspace: JSONDecoder {
        JSONDecoder()
    }
}
