import SwiftUI

public struct LaunchWorkspaceView: View {
    @Bindable var viewModel: WorkspaceViewModel
    private let panels = AppFilePanels()

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Choose a SnowRunner workspace")
                    .font(.title2.weight(.semibold))
                Text("Create one from initial.pak or open a folder containing .snowrunner-workspace.json.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button("Create Workspace From initial.pak") {
                    createWorkspace()
                }
                .buttonStyle(LaunchActionButtonStyle(colorStyle: .main))
                .disabled(viewModel.isBusy)

                Button("Open Existing Workspace Folder") {
                    openWorkspace()
                }
                .buttonStyle(LaunchActionButtonStyle())
                .disabled(viewModel.isBusy)
            }

            if viewModel.isBusy {
                ProgressView()
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .padding(32)
        .frame(maxWidth: 560, maxHeight: .infinity)
    }

    private func createWorkspace() {
        guard let initialPak = panels.chooseInitialPak(),
              let workspace = panels.chooseWorkspaceFolder()
        else { return }
        Task {
            await viewModel.createWorkspace(workspace: workspace, initialPak: initialPak)
        }
    }

    private func openWorkspace() {
        guard let workspace = panels.chooseWorkspaceFolder() else { return }
        Task {
            await viewModel.openWorkspace(workspace)
        }
    }
}

#Preview {
    LaunchWorkspaceView(viewModel: WorkspaceViewModel())
}
