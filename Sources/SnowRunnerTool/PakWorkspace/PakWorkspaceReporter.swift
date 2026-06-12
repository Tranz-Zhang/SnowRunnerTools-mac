import Foundation

public enum PakWorkspaceReporter {
    public static func stdout(result: ModMergeResult, mode: String) -> String {
        "\(mode) workspace\n" + ModMergeReporter.stdout(result: result)
    }

    public static func markdown(result: ModMergeResult) -> String {
        "# Workspace Build Report\n\n" + ModMergeReporter.markdown(result: result)
    }
}
