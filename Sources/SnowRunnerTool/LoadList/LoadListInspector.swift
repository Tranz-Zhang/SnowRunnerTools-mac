import Foundation

public enum LoadListInspector {
    /// Render the manifest as one line per Asset entry, in entry-index order
    /// across phases:
    ///
    ///     <phase>\t<sourcePak>\t<loaderType>\t<manifestPath>
    ///
    /// The returned string ends with exactly one trailing `\n`.
    public static func compactReport(_ manifest: LoadListManifest) -> String {
        var lines: [String] = []
        for phase in manifest.phaseOrder {
            for record in manifest.recordsByPhase[phase] ?? [] {
                lines.append("\(record.phase)\t\(record.sourcePak)\t\(record.loaderType)\t\(record.manifestPath)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
