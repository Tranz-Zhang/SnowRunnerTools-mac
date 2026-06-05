import Foundation

public enum ModMergeReporter {
    public static func stdout(result: ModMergeResult) -> String {
        var lines = [
            "merged \(result.plan.mappedModEntryCount) mod entries",
            "initial overwrites: \(result.plan.collisions.count)",
            "texture overwrites: \(result.plan.textureCollisions.count)",
            "net new initial PAK entries: \(result.plan.netNewOuterPakEntryCount)",
            "net new texture PAK entries: \(result.plan.netNewTexturePakEntryCount)",
            "mod-managed load-list records: \(result.plan.loadListCandidateRecords.count)",
            "texture load-list records: \(result.plan.textureLoadListRecordCount)",
            "net-new load-list records before source overrides: \(result.plan.netNewLoadListRecordCount)",
            "load-list source overrides: \(result.plan.loadListSourceOverrides.count)"
        ]
        if let outputURL = result.outputURL {
            lines.append("written initial: \(outputURL.path)")
        } else {
            lines.append("dry-run initial: no output written")
        }
        if let outputTexturesURL = result.outputTexturesURL {
            lines.append("written textures: \(outputTexturesURL.path)")
        } else if result.plan.textureBaseEntryCount > 0 || result.plan.netNewTexturePakEntryCount > 0 || !result.plan.textureCollisions.isEmpty {
            lines.append("dry-run textures: no output written")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func markdown(result: ModMergeResult) -> String {
        let plan = result.plan
        var lines = [
            "# Mod Merge Report",
            "",
            "- mapped mod entries: \(plan.mappedModEntryCount)",
            "- initial entry replacements: \(plan.collisions.count)",
            "- texture entry replacements: \(plan.textureCollisions.count)",
            "- net new initial PAK entries: \(plan.netNewOuterPakEntryCount)",
            "- net new texture PAK entries: \(plan.netNewTexturePakEntryCount)",
            "- mod-managed load-list records: \(plan.loadListCandidateRecords.count)",
            "- texture load-list records: \(plan.textureLoadListRecordCount)",
            "- net-new load-list records before source overrides: \(plan.netNewLoadListRecordCount)",
            "- load-list source overrides: \(plan.loadListSourceOverrides.count)"
        ]

        if let outputURL = result.outputURL {
            lines.append("- initial output: \(outputURL.path)")
        } else {
            lines.append("- initial output: dry-run")
        }
        if let outputTexturesURL = result.outputTexturesURL {
            lines.append("- texture output: \(outputTexturesURL.path)")
        } else if plan.textureBaseEntryCount > 0 || plan.netNewTexturePakEntryCount > 0 || !plan.textureCollisions.isEmpty {
            lines.append("- texture output: dry-run")
        }

        appendSection("Initial Entry Replacements", values: plan.collisions, into: &lines)
        appendSection("Texture Entry Replacements", values: plan.textureCollisions, into: &lines)
        appendSection("Identical Duplicate Mod Entries", values: plan.duplicateIdenticalMappedNames, into: &lines)
        appendSection(
            "Load-List Source Overrides",
            values: plan.loadListSourceOverrides.map { "\($0.manifestPath): \($0.previousSourcePak) -> \($0.newSourcePak)" },
            into: &lines
        )

        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendSection(_ title: String, values: [String], into lines: inout [String]) {
        lines.append("")
        lines.append("## \(title)")
        if values.isEmpty {
            lines.append("")
            lines.append("None.")
        } else {
            lines.append("")
            for value in values {
                lines.append("- \(value)")
            }
        }
    }
}
