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
