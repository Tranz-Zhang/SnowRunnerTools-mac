import Foundation

public struct LoadListManifest: Equatable {
    /// Version tag from the manifest header (offset 0..3). Observed value is `1`.
    public let versionTag: UInt32

    /// The manifest's header tail u32 (offset 9..12). Observed value is `3`.
    /// Semantics undecided; the parser captures it verbatim and the writer
    /// emits it back unchanged.
    public let headerTail: UInt32

    /// Every entry in the manifest, in entry-index order. Captures dependency
    /// graphs, magic byte arrays, and strings — enough for the writer to
    /// re-emit the manifest byte-for-byte.
    public let entries: [LoadListEntry]

    /// Asset entries grouped by their owning phase tag. The owning phase is
    /// the *next* Stage entry that appears after the asset (per SnowPakTool's
    /// `CreateEntries`).
    public let recordsByPhase: [String: [LoadListRecord]]

    /// Phase tags in write order. Equals `LoadListConstants.phasesInWriteOrder`
    /// for the reference fixture.
    public let phaseOrder: [String]

    public init(
        versionTag: UInt32,
        headerTail: UInt32,
        entries: [LoadListEntry],
        recordsByPhase: [String: [LoadListRecord]],
        phaseOrder: [String]
    ) {
        self.versionTag = versionTag
        self.headerTail = headerTail
        self.entries = entries
        self.recordsByPhase = recordsByPhase
        self.phaseOrder = phaseOrder
    }
}
