import Foundation

public enum LoadListInspector {
    /// Render the same compact entry-order shape emitted by SnowPakTool:
    /// start marker, phase tags, asset manifest paths, and end marker.
    /// The returned string ends with exactly one trailing `\n`.
    public static func compactReport(_ manifest: LoadListManifest) -> String {
        var lines: [String] = []
        for entry in manifest.entries {
            switch entry.kind {
            case .start:
                lines.append("--Start--")
            case .end:
                lines.append("--End--")
            case .stage, .asset:
                lines.append(entry.strings[0])
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
