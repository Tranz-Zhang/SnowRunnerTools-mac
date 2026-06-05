import Foundation

public enum LoadListConstants {
    public static let manifestEntryName = "pak.load_list"
    public static let versionTag: UInt32 = 0x00000001
    public static let marker: UInt8 = 0x01
    /// Captured verbatim from `pak.load_list` in `fixtures/initial.pak`.
    /// Semantics are not documented; the writer emits it back unchanged so
    /// the reference manifest round-trips byte-for-byte.
    public static let headerTail: UInt32 = 0x00000003

    /// The 13 phase tags observed in `pak.load_list` from `fixtures/initial.pak`,
    /// in write order. The format-doc §12.2 list of 8 phases is incomplete; the
    /// parser locks this 13-phase list as the canonical source of truth.
    public static let phasesInWriteOrder: [String] = [
        "RES3_INIT load",
        "SSL_SOURCES_PARSE load",
        "SSL_INITIAL load",
        "TEMPLATES load",
        "CLASSES load",
        "TEXTURE_PREPARE load",
        "TEXTURE load",
        "MESH load",
        "SOUND load",
        "RES3_PROJECT load",
        "PROJECT load",
        "DEFAULT load",
        "DESC_BLOCK load"
    ]

    /// The four source-pak filenames that may appear inline in records of the
    /// reference manifest, in observed first-appearance order across the bytes.
    public static let knownSourcePaks: [String] = [
        "initial.pak",
        "shared_debug.pak",
        "shared.pak",
        "shared_sound.pak",
        "shared_textures_base.pak",
        "shared_textures.pak"
    ]

    public static let knownLoaderTypes: [String] = [
        "spdb",
        "sslbundle",
        "tpl_loader",
        "cls_loader",
        "mesh_loader",
        "sound_loader",
        "pct_mr2_header",
        "pct_faces",
        "pct_inplace_faces"
    ]
}
