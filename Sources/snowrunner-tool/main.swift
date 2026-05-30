import Foundation
import SnowRunnerTool

let result = CLI.run(arguments: Array(CommandLine.arguments.dropFirst()))

if !result.stdout.isEmpty {
    print(result.stdout, terminator: result.stdout.hasSuffix("\n") ? "" : "\n")
}

if !result.stderr.isEmpty {
    fputs(result.stderr.hasSuffix("\n") ? result.stderr : result.stderr + "\n", stderr)
}

exit(result.exitCode)
