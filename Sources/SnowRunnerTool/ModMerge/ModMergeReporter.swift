import Foundation

public enum ModMergeReporter {
    public static func stdout(result: ModMergeResult) -> String {
        var lines = [
            "merged \(result.plan.mappedModEntryCount) mod entries into initial.pak",
            "overwrote \(result.plan.collisions.count) existing entries",
            "mod-managed load-list records: \(result.plan.loadListCandidateRecords.count)",
            "net-new load-list records before source overrides: \(result.plan.netNewLoadListRecordCount)",
            "load-list source overrides: \(result.plan.loadListSourceOverrides.count)"
        ]
        if let outputURL = result.outputURL {
            lines.append("written: \(outputURL.path)")
        } else {
            lines.append("dry-run: no output written")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func markdown(result: ModMergeResult) -> String {
        let plan = result.plan
        var lines = [
            "# Mod Merge Report",
            "",
            "- mapped mod entries: \(plan.mappedModEntryCount)",
            "- base entry replacements: \(plan.collisions.count)",
            "- net new outer PAK entries: \(plan.netNewOuterPakEntryCount)",
            "- mod-managed load-list records: \(plan.loadListCandidateRecords.count)",
            "- net-new load-list records before source overrides: \(plan.netNewLoadListRecordCount)",
            "- load-list source overrides: \(plan.loadListSourceOverrides.count)"
        ]

        if let outputURL = result.outputURL {
            lines.append("- output: \(outputURL.path)")
        } else {
            lines.append("- output: dry-run")
        }

        appendSection("Base Entry Replacements", values: plan.collisions, into: &lines)
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
