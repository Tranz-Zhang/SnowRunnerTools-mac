import Foundation

public struct LoadListRecord: Equatable {
    /// The manifest path, e.g. `<media>\\classes\\trucks\\hummer_h2.xml`. Empty for
    /// phase-control / terminator records that carry no path.
    public let manifestPath: String

    /// The loader-type token, e.g. `cls_loader`. Empty for phase-control /
    /// terminator records that carry no loader type.
    public let loaderType: String

    /// The owning source pak filename, e.g. `initial.pak`. Empty for
    /// phase-control / terminator records that do not embed a source-pak string.
    public let sourcePak: String

    /// The single per-record byte from the manifest's per-record byte table at
    /// offset 13. Observed values in the reference fixture are 0x01, 0x02, 0x05.
    public let flags: UInt8

    /// The owning phase tag, e.g. `DESC_BLOCK load`.
    public let phase: String

    public init(
        manifestPath: String,
        loaderType: String,
        sourcePak: String,
        flags: UInt8,
        phase: String
    ) {
        self.manifestPath = manifestPath
        self.loaderType = loaderType
        self.sourcePak = sourcePak
        self.flags = flags
        self.phase = phase
    }
}
