import Foundation

/// The four entry kinds that can appear in `pak.load_list`. The raw values are
/// the bytes used in the entry-types byte array starting at offset 14 of the
/// manifest, matching SnowPakTool's `LoadListEntryType` enum.
public enum LoadListEntryKind: UInt8, Equatable {
    case stage = 1
    case asset = 2
    case start = 5
    case end = 6
}

/// A single entry parsed from a `pak.load_list` manifest. Captures every byte
/// the writer needs to round-trip the entry exactly: dependencies, the magic
/// byte arrays surrounding the strings, and the strings themselves.
public struct LoadListEntry: Equatable {
    public let kind: LoadListEntryKind

    /// Dependency entry indices in the order they appear in the manifest.
    public let dependsOn: [Int32]

    /// MagicA bytes (length == strings count); each value is 0x01 in
    /// well-formed manifests.
    public let magicA: [UInt8]

    /// MagicB bytes (length == 2); each value is 0x01 in well-formed manifests.
    public let magicB: [UInt8]

    /// Length-prefixed CP437 strings owned by this entry. Layout per kind:
    ///   - `start`/`end`: empty
    ///   - `stage`: `[text]` (e.g. `"DESC_BLOCK load"`)
    ///   - `asset`: `[internalName, loader, pakName]` or
    ///     `[internalName, loader, pakName, json]`.
    public let strings: [String]

    public init(
        kind: LoadListEntryKind,
        dependsOn: [Int32],
        magicA: [UInt8],
        magicB: [UInt8],
        strings: [String]
    ) {
        self.kind = kind
        self.dependsOn = dependsOn
        self.magicA = magicA
        self.magicB = magicB
        self.strings = strings
    }
}
