import Foundation

public struct CLIResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum CLI {
    public static func run(arguments: [String]) -> CLIResult {
        guard !arguments.isEmpty else {
            return CLIResult(exitCode: 2, stdout: "", stderr: usage())
        }

        if arguments.first == "cache-block" {
            return runCacheBlockCommand(Array(arguments.dropFirst()))
        }

        if arguments.first == "load-list" {
            return runLoadListCommand(Array(arguments.dropFirst()))
        }

        guard arguments.first == "pak" else {
            return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown command: \(arguments[0])\n\n\(usage())")
        }

        return runPakCommand(Array(arguments.dropFirst()))
    }

    private static func usage() -> String {
        """
        Usage: snowrunner-tool pak <command> [arguments]

        Commands:
          cache-block unpack <cache_block> <dir>
          cache-block pack <dir> <cache_block>
          cache-block verify-content-equivalent <reference.cache_block> <candidate.cache_block>
          load-list inspect <pak.load_list>
          load-list create-initial <target.load_list> <initial.pak> <shared.pak> <shared_sound.pak>
          pak inspect <pak>
          pak unpack <pak> <dir>
          pak pack <dir> <pak>
          pak pack --mixed-cache-block <dir> <pak>
          pak pack --rebuild-load-list [--mixed-cache-block] <dir> <pak> <shared.pak> <shared_sound.pak>
          pak merge-mod [--allow-overwrite] [--dry-run] [--report <path>] --input-initial <base-initial.pak> --output-initial <output-initial.pak> [--input-textures <shared_textures_base.pak> --output-textures <candidate-base-textures.pak>] [--input-shared-textures <shared_textures.pak> --output-shared-textures <candidate-shared_textures.pak>] --mods <mod.pak> [<mod.pak> ...]
          pak merge-mod [--allow-overwrite] [--dry-run] [--report <path>] --input-initial <base-initial.pak> --output-initial <output-initial.pak> --experimental-output-mod-textures <mod_textures.pak> --mods <mod.pak> [<mod.pak> ...]
          pak merge-mod [--allow-overwrite] [--dry-run] [--report <path>] --input-initial <base-initial.pak> --output-initial <output-initial.pak> --experimental-inline-textures --mods <mod.pak> [<mod.pak> ...]
          pak verify-basic <pak>
          pak verify-content-equivalent <reference.pak> <candidate.pak>
          pak verify-snowpak-layout <pak>
        """
    }

    private static func runCacheBlockCommand(_ arguments: [String]) -> CLIResult {
        guard let command = arguments.first else {
            return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown cache-block command\n\n\(usage())")
        }

        do {
            switch command {
            case "unpack":
                guard arguments.count == 3 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool cache-block unpack <cache_block> <dir>\n")
                }
                let count = try CacheBlockUnpacker.unpack(
                    cacheBlockURL: URL(fileURLWithPath: arguments[1]),
                    toDirectory: URL(fileURLWithPath: arguments[2], isDirectory: true)
                )
                return CLIResult(exitCode: 0, stdout: "unpacked \(count) cache-block entries\n", stderr: "")

            case "pack":
                guard arguments.count == 3 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool cache-block pack <dir> <cache_block>\n")
                }
                let count = try CacheBlockWriter.writeArchive(
                    fromDirectory: URL(fileURLWithPath: arguments[1], isDirectory: true),
                    to: URL(fileURLWithPath: arguments[2])
                )
                return CLIResult(exitCode: 0, stdout: "packed \(count) cache-block entries\n", stderr: "")

            case "verify-content-equivalent":
                guard arguments.count == 3 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool cache-block verify-content-equivalent <reference.cache_block> <candidate.cache_block>\n")
                }
                let reference = try CacheBlockReader.readArchive(at: URL(fileURLWithPath: arguments[1]))
                let candidate = try CacheBlockReader.readArchive(at: URL(fileURLWithPath: arguments[2]))
                let issues = try CacheBlockVerifier.verifyContentEquivalent(reference: reference, candidate: candidate)
                return verifierResult(name: "cache-block verify-content-equivalent", issues: issues)

            default:
                return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown cache-block command: \(command)\n\n\(usage())")
            }
        } catch {
            return CLIResult(exitCode: 1, stdout: "", stderr: "\(error)\n")
        }
    }

    private static func runLoadListCommand(_ arguments: [String]) -> CLIResult {
        guard let command = arguments.first else {
            return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown load-list command\n\n\(usage())")
        }

        do {
            switch command {
            case "inspect":
                guard arguments.count == 2 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool load-list inspect <pak.load_list>\n")
                }
                let manifest = try LoadListReader.readManifest(from: URL(fileURLWithPath: arguments[1]))
                return CLIResult(exitCode: 0, stdout: LoadListInspector.compactReport(manifest), stderr: "")

            case "create-initial":
                guard arguments.count == 5 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool load-list create-initial <target.load_list> <initial.pak> <shared.pak> <shared_sound.pak>\n")
                }
                let manifest = try LoadListBuilder.buildManifestFromPaks(inputs: .init(
                    initialPak: URL(fileURLWithPath: arguments[2]),
                    sharedPak: URL(fileURLWithPath: arguments[3]),
                    sharedSoundPak: URL(fileURLWithPath: arguments[4])
                ))
                try LoadListWriter.writeManifest(manifest, to: URL(fileURLWithPath: arguments[1]))
                let total = manifest.phaseOrder.reduce(0) { $0 + (manifest.recordsByPhase[$1]?.count ?? 0) }
                return CLIResult(
                    exitCode: 0,
                    stdout: "created load-list with \(total) records across \(manifest.phaseOrder.count) phases\n",
                    stderr: ""
                )

            default:
                return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown load-list command: \(command)\n\n\(usage())")
            }
        } catch {
            return CLIResult(exitCode: 1, stdout: "", stderr: "\(error)\n")
        }
    }

    private static func runPakCommand(_ arguments: [String]) -> CLIResult {
        guard let command = arguments.first else {
            return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown pak command\n\n\(usage())")
        }

        do {
            switch command {
            case "inspect":
                guard arguments.count == 2 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool pak inspect <pak>\n")
                }
                let archive = try PakReader.readArchive(at: URL(fileURLWithPath: arguments[1]))
                return CLIResult(exitCode: 0, stdout: inspectOutput(for: archive), stderr: "")

            case "unpack":
                guard arguments.count == 3 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool pak unpack <pak> <dir>\n")
                }
                let count = try PakUnpacker.unpack(
                    archiveURL: URL(fileURLWithPath: arguments[1]),
                    toDirectory: URL(fileURLWithPath: arguments[2], isDirectory: true)
                )
                return CLIResult(exitCode: 0, stdout: "unpacked \(count) entries\n", stderr: "")

            case "pack":
                return try runPakPackCommand(Array(arguments.dropFirst()))

            case "merge-mod":
                return try runPakMergeModCommand(Array(arguments.dropFirst()))

            case "verify-basic":
                guard arguments.count == 2 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool pak verify-basic <pak>\n")
                }
                let archive = try PakReader.readArchive(at: URL(fileURLWithPath: arguments[1]))
                let issues = try PakVerifier.verifyBasic(archive)
                return verifierResult(name: "verify-basic", issues: issues)

            case "verify-content-equivalent":
                guard arguments.count == 3 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool pak verify-content-equivalent <reference.pak> <candidate.pak>\n")
                }
                let reference = try PakReader.readArchive(at: URL(fileURLWithPath: arguments[1]))
                let candidate = try PakReader.readArchive(at: URL(fileURLWithPath: arguments[2]))
                let issues = try PakVerifier.verifyContentEquivalent(reference: reference, candidate: candidate)
                return verifierResult(name: "verify-content-equivalent", issues: issues)

            case "verify-snowpak-layout":
                guard arguments.count == 2 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool pak verify-snowpak-layout <pak>\n")
                }
                let archive = try PakReader.readArchive(at: URL(fileURLWithPath: arguments[1]))
                let issues = try PakVerifier.verifySnowPakLayout(archive)
                return verifierResult(name: "verify-snowpak-layout", issues: issues)

            default:
                return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown pak command: \(command)\n\n\(usage())")
            }
        } catch {
            return CLIResult(exitCode: 1, stdout: "", stderr: "\(error)\n")
        }
    }

    private static func runPakPackCommand(_ arguments: [String]) throws -> CLIResult {
        var flags: Set<String> = []
        var index = 0
        while index < arguments.count, arguments[index].hasPrefix("--") {
            let flag = arguments[index]
            guard flag == "--mixed-cache-block" || flag == "--rebuild-load-list" else {
                return CLIResult(exitCode: 2, stdout: "", stderr: pakPackUsage())
            }
            guard !flags.contains(flag) else {
                return CLIResult(exitCode: 2, stdout: "", stderr: pakPackUsage())
            }
            flags.insert(flag)
            index += 1
        }

        let positionals = Array(arguments[index...])
        let rebuildLoadList = flags.contains("--rebuild-load-list")
        let mixedCacheBlock = flags.contains("--mixed-cache-block")
        let expectedCount = rebuildLoadList ? 4 : 2
        guard positionals.count == expectedCount else {
            return CLIResult(exitCode: 2, stdout: "", stderr: pakPackUsage())
        }

        let directory = URL(fileURLWithPath: positionals[0], isDirectory: true)
        let outputURL = URL(fileURLWithPath: positionals[1])

        let count: Int
        if rebuildLoadList {
            count = try PakWriter.writeArchive(
                fromDirectory: directory,
                to: outputURL,
                rebuildLoadList: true,
                mixedCacheBlock: mixedCacheBlock,
                sharedPak: URL(fileURLWithPath: positionals[2]),
                sharedSoundPak: URL(fileURLWithPath: positionals[3])
            )
        } else if mixedCacheBlock {
            count = try PakWriter.writeArchive(
                fromDirectory: directory,
                to: outputURL,
                mixedCacheBlock: true
            )
        } else {
            count = try PakWriter.writeArchive(
                fromDirectory: directory,
                to: outputURL
            )
        }
        return CLIResult(exitCode: 0, stdout: "packed \(count) entries\n", stderr: "")
    }

    private static func pakPackUsage() -> String {
        "Usage: snowrunner-tool pak pack [--rebuild-load-list] [--mixed-cache-block] <dir> <pak> [<shared.pak> <shared_sound.pak>]\n"
    }

    private static func runPakMergeModCommand(_ arguments: [String]) throws -> CLIResult {
        var allowOverwrite = false
        var dryRun = false
        var reportPath: String?
        var inputInitialPath: String?
        var outputInitialPath: String?
        var inputTexturesPath: String?
        var outputTexturesPath: String?
        var inputSharedTexturesPath: String?
        var outputSharedTexturesPath: String?
        var experimentalModTexturesOutputPath: String?
        var experimentalInlineTextures = false
        var modPaths: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--allow-overwrite":
                guard !allowOverwrite else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                allowOverwrite = true
                index += 1
            case "--dry-run":
                guard !dryRun else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                dryRun = true
                index += 1
            case "--report":
                guard reportPath == nil, index + 1 < arguments.count else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                reportPath = arguments[index + 1]
                index += 2
            case "--input-initial":
                guard inputInitialPath == nil, index + 1 < arguments.count else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                inputInitialPath = arguments[index + 1]
                index += 2
            case "--output-initial":
                guard outputInitialPath == nil, index + 1 < arguments.count else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                outputInitialPath = arguments[index + 1]
                index += 2
            case "--input-textures":
                guard inputTexturesPath == nil, index + 1 < arguments.count else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                inputTexturesPath = arguments[index + 1]
                index += 2
            case "--output-textures":
                guard outputTexturesPath == nil, index + 1 < arguments.count else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                outputTexturesPath = arguments[index + 1]
                index += 2
            case "--input-shared-textures":
                guard inputSharedTexturesPath == nil, index + 1 < arguments.count else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                inputSharedTexturesPath = arguments[index + 1]
                index += 2
            case "--output-shared-textures":
                guard outputSharedTexturesPath == nil, index + 1 < arguments.count else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                outputSharedTexturesPath = arguments[index + 1]
                index += 2
            case "--experimental-output-mod-textures":
                guard experimentalModTexturesOutputPath == nil, index + 1 < arguments.count else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                experimentalModTexturesOutputPath = arguments[index + 1]
                index += 2
            case "--experimental-inline-textures":
                guard !experimentalInlineTextures else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                experimentalInlineTextures = true
                index += 1
            case "--mods":
                let remaining = Array(arguments[(index + 1)...])
                guard !remaining.isEmpty, remaining.allSatisfy({ !$0.hasPrefix("--") }) else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
                }
                modPaths = remaining
                index = arguments.count
            default:
                return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
            }
        }

        guard let inputInitialPath,
              let outputInitialPath,
              !modPaths.isEmpty else {
            return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
        }
        guard !(experimentalInlineTextures && experimentalModTexturesOutputPath != nil) else {
            return CLIResult(exitCode: 2, stdout: "", stderr: pakMergeModUsage())
        }

        let base = URL(fileURLWithPath: inputInitialPath)
        let output = URL(fileURLWithPath: outputInitialPath)
        let inputTextures = inputTexturesPath.map { URL(fileURLWithPath: $0) }
        let outputTextures = outputTexturesPath.map { URL(fileURLWithPath: $0) }
        let inputSharedTextures = inputSharedTexturesPath.map { URL(fileURLWithPath: $0) }
        let outputSharedTextures = outputSharedTexturesPath.map { URL(fileURLWithPath: $0) }
        let experimentalModTexturesOutput = experimentalModTexturesOutputPath.map { URL(fileURLWithPath: $0) }
        let mods = modPaths.map { URL(fileURLWithPath: $0) }
        let options = ModMergeOptions(
            allowOverwrite: allowOverwrite,
            dryRun: dryRun,
            reportURL: reportPath.map { URL(fileURLWithPath: $0) },
            experimentalModTexturesOutputURL: experimentalModTexturesOutput,
            experimentalInlineTextures: experimentalInlineTextures
        )
        let result = try ModMerger.merge(
            baseInitialPak: base,
            outputInitialPak: output,
            baseSharedTexturesPak: inputTextures,
            outputSharedTexturesPak: outputTextures,
            baseHighSharedTexturesPak: inputSharedTextures,
            outputHighSharedTexturesPak: outputSharedTextures,
            modPaks: mods,
            options: options
        )
        return CLIResult(exitCode: 0, stdout: ModMergeReporter.stdout(result: result), stderr: "")
    }

    private static func pakMergeModUsage() -> String {
        "Usage: snowrunner-tool pak merge-mod [--allow-overwrite] [--dry-run] [--report <path>] --input-initial <base-initial.pak> --output-initial <output-initial.pak> [--input-textures <shared_textures_base.pak> --output-textures <candidate-base-textures.pak>] [--input-shared-textures <shared_textures.pak> --output-shared-textures <candidate-shared_textures.pak>] [--experimental-output-mod-textures <mod_textures.pak> | --experimental-inline-textures] --mods <mod.pak> [<mod.pak> ...]\n"
    }

    private static func inspectOutput(for archive: PakArchive) -> String {
        let storedCount = archive.entries.filter { $0.compressionMethod == .stored }.count
        let deflatedCount = archive.entries.filter { $0.compressionMethod == .deflated }.count
        let first = archive.entries.first

        return """
        entries: \(archive.entries.count)
        stored: \(storedCount)
        deflated: \(deflatedCount)
        first entry: \(first?.name ?? "<none>")
        first method: \(first?.compressionMethod.description ?? "<none>")
        central directory offset: \(archive.centralDirectoryOffset)
        central directory size: \(archive.centralDirectorySize)
        """
    }

    private static func verifierResult(name: String, issues: [VerifierIssue]) -> CLIResult {
        guard !issues.isEmpty else {
            return CLIResult(exitCode: 0, stdout: "PASS \(name)\n", stderr: "")
        }

        let output = issues.map { "\($0.severity.rawValue) \($0.code): \($0.message)" }.joined(separator: "\n") + "\n"
        return CLIResult(exitCode: 1, stdout: output, stderr: "")
    }
}

private extension ZipCompressionMethod {
    var description: String {
        switch self {
        case .stored:
            return "stored"
        case .deflated:
            return "deflated"
        }
    }
}
