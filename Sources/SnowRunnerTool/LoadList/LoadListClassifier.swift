import Foundation

public struct LoadListClassificationInput: Equatable {
    public let internalName: String
    public let sourcePak: String

    public init(internalName: String, sourcePak: String) {
        self.internalName = internalName
        self.sourcePak = sourcePak
    }
}

/// Classifies a single PAK entry into the `LoadListRecord` shape used by the
/// reference manifest. Rules are derived from the parsed reference manifest
/// extracted from `fixtures/initial.pak`'s `pak.load_list` (17,902 records,
/// six unique `(loader, source-pak)` tuples). Entries that intentionally do
/// not appear in the manifest (the manifest itself, the cache-block, loose
/// `[strings]`, the `[ssl_cache]\initial_pak` marker) classify to `nil`.
/// Path shapes that match no rule throw `LoadListError.invalidManifestPath`.
public enum LoadListClassifier {
    public static func classify(_ input: LoadListClassificationInput) throws -> LoadListRecord? {
        let name = input.internalName

        // Entries that exist in PAKs but are never recorded in pak.load_list.
        switch name {
        case LoadListConstants.manifestEntryName,
             "initial.cache_block",
             "[ssl_cache]\\initial_pak":
            return nil
        default:
            break
        }
        if name.hasPrefix("[strings]\\") {
            return nil
        }
        if name.hasPrefix("[sound]\\") || name.hasPrefix("[ps]\\") || name.hasPrefix("[ps_common]\\") {
            return nil
        }

        let manifestPath = convertNamespaceBrackets(name)

        // Rule P1: lone sound list — no namespace prefix.
        if manifestPath == "sound.sound_list", input.sourcePak == "shared_sound.pak" {
            return LoadListRecord(
                manifestPath: manifestPath,
                loaderType: "sound_loader",
                sourcePak: "shared_sound.pak",
                json: nil,
                phase: "SOUND load"
            )
        }

        // Rule P2: <ssl_cache>\*.spdb -> spdb / shared_debug.pak / SSL_INITIAL.
        if manifestPath.hasPrefix("<ssl_cache>\\"), manifestPath.hasSuffix(".spdb") {
            return LoadListRecord(
                manifestPath: manifestPath,
                loaderType: "spdb",
                sourcePak: "shared_debug.pak",
                json: nil,
                phase: "SSL_INITIAL load"
            )
        }

        // Rule P3: <ssl_cache>\*.sslbundle -> sslbundle / initial.pak.
        if manifestPath.hasPrefix("<ssl_cache>\\"), manifestPath.hasSuffix(".sslbundle") {
            return LoadListRecord(
                manifestPath: manifestPath,
                loaderType: "sslbundle",
                sourcePak: "initial.pak",
                json: nil,
                phase: "SSL_INITIAL load"
            )
        }

        // Rule P4: <meshes>\NAME -> mesh_loader / shared.pak / MESH.
        if manifestPath.hasPrefix("<meshes>\\") {
            return LoadListRecord(
                manifestPath: manifestPath,
                loaderType: "mesh_loader",
                sourcePak: "shared.pak",
                json: nil,
                phase: "MESH load"
            )
        }

        // Rule P5: <media>\_templates\*.xml -> tpl_loader / initial.pak / TEMPLATES.
        if manifestPath.hasPrefix("<media>\\_templates\\"), manifestPath.hasSuffix(".xml") {
            return LoadListRecord(
                manifestPath: manifestPath,
                loaderType: "tpl_loader",
                sourcePak: "initial.pak",
                json: nil,
                phase: "TEMPLATES load"
            )
        }

        // Rule P6: <media>\…\classes\…\*.xml -> cls_loader / initial.pak / CLASSES.
        if manifestPath.hasPrefix("<media>\\"),
           manifestPath.hasSuffix(".xml"),
           manifestPath.contains("\\classes\\") {
            return LoadListRecord(
                manifestPath: manifestPath,
                loaderType: "cls_loader",
                sourcePak: "initial.pak",
                json: nil,
                phase: "CLASSES load"
            )
        }

        throw LoadListError.invalidManifestPath(name)
    }

    /// Classifier for mod entries that have already been mapped into the
    /// merge runtime namespace. It preserves the strict full-rebuild classifier
    /// while allowing v1 mod payloads that intentionally do not get load-list
    /// records.
    public static func classifyMergedInitialModEntry(_ internalName: String) throws -> LoadListRecord? {
        try classifyMergedModEntry(internalName).first
    }

    public static func classifyMergedModEntry(
        _ internalName: String,
        textureSourcePak: String = "shared_textures.pak"
    ) throws -> [LoadListRecord] {
        if internalName.hasPrefix("[ui]\\") || internalName.hasPrefix("[strings]\\") {
            return []
        }

        let manifestPath = convertNamespaceBrackets(internalName)

        if manifestPath.hasPrefix("<textures>\\pct\\"), manifestPath.hasSuffix(".pct_header") {
            return [
                LoadListRecord(
                    manifestPath: manifestPath,
                    loaderType: "pct_mr2_header",
                    sourcePak: textureSourcePak,
                    json: nil,
                    phase: "TEXTURE load"
                ),
                LoadListRecord(
                    manifestPath: manifestPath,
                    loaderType: "pct_faces",
                    sourcePak: textureSourcePak,
                    json: nil,
                    phase: "TEXTURE load"
                )
            ]
        }

        if manifestPath.hasPrefix("<textures>\\") {
            return []
        }

        if manifestPath.hasPrefix("<media>\\_templates\\"), manifestPath.hasSuffix(".xml") {
            return [LoadListRecord(
                manifestPath: manifestPath,
                loaderType: "tpl_loader",
                sourcePak: "initial.pak",
                json: nil,
                phase: "TEMPLATES load"
            )]
        }

        if manifestPath.hasPrefix("<media>\\"),
           manifestPath.hasSuffix(".xml"),
           manifestPath.contains("\\classes\\") {
            return [LoadListRecord(
                manifestPath: manifestPath,
                loaderType: "cls_loader",
                sourcePak: "initial.pak",
                json: nil,
                phase: "CLASSES load"
            )]
        }

        if manifestPath.hasPrefix("<ssl_cache>\\"), manifestPath.hasSuffix(".sslbundle") {
            return [LoadListRecord(
                manifestPath: manifestPath,
                loaderType: "sslbundle",
                sourcePak: "initial.pak",
                json: nil,
                phase: "SSL_INITIAL load"
            )]
        }

        if manifestPath.hasPrefix("<meshes>\\") {
            return [LoadListRecord(
                manifestPath: manifestPath,
                loaderType: "mesh_loader",
                sourcePak: "initial.pak",
                json: nil,
                phase: "MESH load"
            )]
        }

        throw LoadListError.invalidManifestPath(internalName)
    }

    /// Convert `[namespace]\rest` to `<namespace>\rest`. Leaves paths without
    /// a leading bracketed namespace unchanged.
    private static func convertNamespaceBrackets(_ name: String) -> String {
        guard name.first == "[" else { return name }
        guard let closing = name.firstIndex(of: "]") else { return name }
        let namespace = name[name.index(after: name.startIndex)..<closing]
        let rest = name[name.index(after: closing)...]
        return "<\(namespace)>\(rest)"
    }
}
