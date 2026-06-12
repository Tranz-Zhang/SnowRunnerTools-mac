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
    public var entries: [PakWorkspaceSourceEntry]

    public init(
        sourcePath: String,
        folderName: String,
        archiveName: String,
        sourceCachePath: String,
        entries: [PakWorkspaceSourceEntry]
    ) {
        self.sourcePath = sourcePath
        self.folderName = folderName
        self.archiveName = archiveName
        self.sourceCachePath = sourceCachePath
        self.entries = entries
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
