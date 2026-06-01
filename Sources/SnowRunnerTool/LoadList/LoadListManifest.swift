import Foundation

public struct LoadListManifest: Equatable {
    /// Version tag from the manifest header (offset 0..3). Observed value is `1`.
    public let versionTag: UInt32

    /// The manifest's header tail u32 (offset 9..12). Observed value is `3`. Its
    /// semantics are undecided; the parser captures it verbatim and the writer
    /// emits it back unchanged.
    public let headerTail: UInt32

    /// Per-record byte table at offset 13 of the manifest, length equal to the
    /// total record count. Observed values in the reference fixture are 0x01,
    /// 0x02, 0x05. The parser captures these verbatim; the writer emits them
    /// back unchanged.
    public let recordFlags: [UInt8]

    /// Records grouped by owning phase tag.
    public let recordsByPhase: [String: [LoadListRecord]]

    /// Phase tags in write order. Must equal `LoadListConstants.phasesInWriteOrder`
    /// for the reference fixture.
    public let phaseOrder: [String]

    public init(
        versionTag: UInt32,
        headerTail: UInt32,
        recordFlags: [UInt8],
        recordsByPhase: [String: [LoadListRecord]],
        phaseOrder: [String]
    ) {
        self.versionTag = versionTag
        self.headerTail = headerTail
        self.recordFlags = recordFlags
        self.recordsByPhase = recordsByPhase
        self.phaseOrder = phaseOrder
    }
}
