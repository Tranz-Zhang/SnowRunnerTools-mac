import SwiftUI
import SnowRunnerTool

public struct ConflictDetailsView: View {
    @Bindable var viewModel: WorkspaceViewModel

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conflict Details")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Back to Workspace") {
                    viewModel.showWorkspace()
                }
                .keyboardShortcut(.cancelAction)
            }

            if conflicts.isEmpty {
                Text("No conflicts found.")
                    .foregroundStyle(.secondary)
            } else {
                List(conflicts) { conflict in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(conflict.targetPath)
                            .font(.callout.weight(.semibold))
                            .textSelection(.enabled)
                        Text(conflict.mods.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var conflicts: [WorkspaceModConflict] {
        viewModel.quickVerifyResult?.conflicts ?? []
    }
}

#Preview {
    ConflictDetailsView(viewModel: ConflictDetailsPreview.viewModel)
        .frame(width: 720, height: 420)
}

private enum ConflictDetailsPreview {
    @MainActor
    static var viewModel: WorkspaceViewModel {
        let workspace = URL(fileURLWithPath: "/Users/demo/SnowRunnerWorkspace", isDirectory: true)
        let model = WorkspaceViewModel()
        model.screen = .conflictDetails
        model.summary = PakWorkspaceSummary(
            workspace: workspace,
            initialSourcePath: "/Applications/SnowRunner/preload/paks/client/initial.pak",
            mods: [],
            buildInitialPak: workspace.appendingPathComponent("build/initial.pak"),
            buildReport: workspace.appendingPathComponent("build/workspace-build-report.md")
        )
        model.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [
            WorkspaceModConflict(
                targetPath: "initial.pak/classes/trucks/azov_64131.xml",
                mods: ["azov-tuning-pack", "loadstar-rescue-kit"]
            ),
            WorkspaceModConflict(
                targetPath: "initial.pak/classes/wheels/offroad.xml",
                mods: ["loadstar-rescue-kit", "trail-wheel-pack"]
            )
        ])
        return model
    }
}
