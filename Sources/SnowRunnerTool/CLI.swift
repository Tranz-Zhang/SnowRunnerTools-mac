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

        guard arguments.first == "pak" else {
            return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown command: \(arguments[0])\n\n\(usage())")
        }

        return CLIResult(exitCode: 2, stdout: "", stderr: "Unknown pak command\n\n\(usage())")
    }

    private static func usage() -> String {
        """
        Usage: snowrunner-tool pak <command> [arguments]

        Commands:
          pak inspect <pak>
          pak verify-basic <pak>
          pak verify-content-equivalent <reference.pak> <candidate.pak>
          pak verify-snowpak-layout <pak>
        """
    }
}
