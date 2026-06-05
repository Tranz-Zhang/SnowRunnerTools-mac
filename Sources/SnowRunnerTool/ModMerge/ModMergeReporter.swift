import Foundation

public enum ModMergeReporter {
    public static func stdout(result: ModMergeResult) -> String {
        var lines = [
            "merged \(result.plan.mappedModEntryCount) mod entries",
            "initial overwrites: \(result.plan.collisions.count)",
            "texture overwrites: \(result.plan.textureCollisions.count)",
            "shared texture overwrites: \(result.plan.sharedTextureCollisions.count)",
            "string table merges: \(result.plan.stringMergeEntryCount)",
            "net new initial PAK entries: \(result.plan.netNewOuterPakEntryCount)",
            "net new texture PAK entries: \(result.plan.netNewTexturePakEntryCount)",
            "net new shared texture PAK entries: \(result.plan.netNewSharedTexturePakEntryCount)",
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
        } else if result.outputSharedTexturesURL == nil
            && !result.plan.texturesInInitial
            && (result.plan.textureBaseEntryCount > 0
                || result.plan.netNewTexturePakEntryCount > 0
                || !result.plan.textureCollisions.isEmpty) {
            lines.append("dry-run textures: no output written")
        }
        if let outputSharedTexturesURL = result.outputSharedTexturesURL {
            lines.append("written shared textures: \(outputSharedTexturesURL.path)")
        } else if !result.plan.texturesInInitial
            && (result.plan.sharedTextureEntryCount > 0
                || result.plan.netNewSharedTexturePakEntryCount > 0
                || !result.plan.sharedTextureCollisions.isEmpty) {
            lines.append("dry-run shared textures: no output written")
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
            "- shared texture entry replacements: \(plan.sharedTextureCollisions.count)",
            "- string table merges: \(plan.stringMergeEntryCount)",
            "- net new initial PAK entries: \(plan.netNewOuterPakEntryCount)",
            "- net new texture PAK entries: \(plan.netNewTexturePakEntryCount)",
            "- net new shared texture PAK entries: \(plan.netNewSharedTexturePakEntryCount)",
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
        } else if result.outputSharedTexturesURL == nil
            && !plan.texturesInInitial
            && (plan.textureBaseEntryCount > 0
                || plan.netNewTexturePakEntryCount > 0
                || !plan.textureCollisions.isEmpty) {
            lines.append("- texture output: dry-run")
        }
        if let outputSharedTexturesURL = result.outputSharedTexturesURL {
            lines.append("- shared texture output: \(outputSharedTexturesURL.path)")
        } else if !plan.texturesInInitial
            && (plan.sharedTextureEntryCount > 0
                || plan.netNewSharedTexturePakEntryCount > 0
                || !plan.sharedTextureCollisions.isEmpty) {
            lines.append("- shared texture output: dry-run")
        }

        appendSection("Initial Entry Replacements", values: plan.collisions, into: &lines)
        appendSection("Texture Entry Replacements", values: plan.textureCollisions, into: &lines)
        appendSection("Shared Texture Entry Replacements", values: plan.sharedTextureCollisions, into: &lines)
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
