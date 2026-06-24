import SwiftUI

public struct LaunchWorkspaceView: View {
    @Bindable var viewModel: WorkspaceViewModel
    private let panels = AppFilePanels()

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("snowrunner_title")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 420)
                .accessibilityLabel("SnowRunner")
                .accessibilityAddTraits(.isHeader)
            Spacer()
            VStack(spacing: 10) {
                Button("Create Workspace From initial.pak") {
                    createWorkspace()
                }
                .buttonStyle(SRButtonStyle(colorStyle: .darkGray, minWidth: 250))
                .disabled(viewModel.isBusy)

                Button("Open Existing Workspace Folder") {
                    openWorkspace()
                }
                .buttonStyle(SRButtonStyle(colorStyle: .normal, minWidth: 250))
                .disabled(viewModel.isBusy)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if viewModel.isBusy {
                ProgressView()
                    .padding(15)
            }
        }
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
        .frame(width: 880, height: 560)
}
