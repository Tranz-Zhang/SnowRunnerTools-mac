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
          pak inspect <pak>
          pak unpack <pak> <dir>
          pak pack <dir> <pak>
          pak pack --mixed-cache-block <dir> <pak>
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
                if arguments.count == 4, arguments[1] == "--mixed-cache-block" {
                    let count = try PakWriter.writeArchive(
                        fromDirectory: URL(fileURLWithPath: arguments[2], isDirectory: true),
                        to: URL(fileURLWithPath: arguments[3]),
                        mixedCacheBlock: true
                    )
                    return CLIResult(exitCode: 0, stdout: "packed \(count) entries\n", stderr: "")
                }

                guard arguments.count == 3 else {
                    return CLIResult(exitCode: 2, stdout: "", stderr: "Usage: snowrunner-tool pak pack [--mixed-cache-block] <dir> <pak>\n")
                }
                let count = try PakWriter.writeArchive(
                    fromDirectory: URL(fileURLWithPath: arguments[1], isDirectory: true),
                    to: URL(fileURLWithPath: arguments[2])
                )
                return CLIResult(exitCode: 0, stdout: "packed \(count) entries\n", stderr: "")

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
