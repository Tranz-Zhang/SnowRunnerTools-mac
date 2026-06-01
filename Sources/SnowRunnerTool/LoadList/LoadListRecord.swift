import Foundation

/// A high-level view of a single Asset entry parsed from `pak.load_list`.
/// Phase-control entries (Start/End/Stage) are captured at the lower
/// `LoadListEntry` level and are not exposed here.
public struct LoadListRecord: Equatable {
    /// The manifest path, e.g. `<media>\\classes\\trucks\\hummer_h2.xml`.
    public let manifestPath: String

    /// The loader-type token, e.g. `cls_loader`.
    public let loaderType: String

    /// The owning source pak filename, e.g. `initial.pak`.
    public let sourcePak: String

    /// Optional fourth string (`Json` in SnowPakTool). Present only when an
    /// Asset entry carries 4 strings instead of 3. Always `nil` for records
    /// in the reference fixture.
    public let json: String?

    /// The owning phase tag, e.g. `CLASSES load`.
    public let phase: String

    public init(
        manifestPath: String,
        loaderType: String,
        sourcePak: String,
        json: String? = nil,
        phase: String
    ) {
        self.manifestPath = manifestPath
        self.loaderType = loaderType
        self.sourcePak = sourcePak
        self.json = json
        self.phase = phase
    }
}
