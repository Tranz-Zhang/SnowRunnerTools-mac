import Foundation

public enum WorkspaceInitialLoadListBuilder {
    public static func records(
        fromInitialDirectory directory: URL,
        preservingFrom baseManifest: LoadListManifest
    ) throws -> [LoadListRecord] {
        let preserved = baseManifest.phaseOrder
            .flatMap { baseManifest.recordsByPhase[$0] ?? [] }
            .filter { $0.sourcePak != "initial.pak" }

        let sources = try scanInitialDirectory(directory)
        let rebuilt = try sources.flatMap { try classifyInitialSource($0.internalName) }
        return preserved + rebuilt
    }

    public static func classifyInitialSource(_ internalName: String) throws -> [LoadListRecord] {
        if internalName == LoadListConstants.manifestEntryName
            || internalName == CacheBlockConstants.initialCacheBlockName
            || internalName == "[ssl_cache]\\initial_pak" {
            return []
        }
        if internalName.hasPrefix("[strings]\\")
            || internalName.hasPrefix("[sound]\\")
            || internalName.hasPrefix("[ps]\\")
            || internalName.hasPrefix("[ps_common]\\")
            || internalName.hasPrefix("[ui]\\") {
            return []
        }
        if internalName.hasPrefix("[textures]\\") {
            if internalName.hasPrefix("[textures]\\pct\\") && internalName.hasSuffix(".pct_header") {
                let manifestPath = convertNamespaceBrackets(internalName)
                return [
                    LoadListRecord(
                        manifestPath: manifestPath,
                        loaderType: "pct_mr2_header",
                        sourcePak: "initial.pak",
                        phase: "TEXTURE load"
                    ),
                    LoadListRecord(
                        manifestPath: manifestPath,
                        loaderType: "pct_faces",
                        sourcePak: "initial.pak",
                        phase: "TEXTURE load"
                    )
                ]
            }
            return []
        }

        return try LoadListClassifier.classifyMergedModEntry(internalName, textureSourcePak: "initial.pak")
    }

    private static func convertNamespaceBrackets(_ name: String) -> String {
        guard name.first == "[", let closing = name.firstIndex(of: "]") else {
            return name
        }
        let namespace = name[name.index(after: name.startIndex)..<closing]
        let rest = name[name.index(after: closing)...]
        return "<\(namespace)>\(rest)"
    }

    private static func scanInitialDirectory(_ directory: URL) throws -> [PakFileSource] {
        let root = directory.standardizedFileURL
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var sources: [PakFileSource] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else {
                continue
            }

            let internalName = try PakPath.internalName(forFileAt: fileURL, rootDirectory: root)
            sources.append(PakFileSource(internalName: internalName, fileURL: fileURL))
        }

        return try PakDirectoryScanner.sortedPackSources(sources, requirePakLoadList: false)
    }
}
