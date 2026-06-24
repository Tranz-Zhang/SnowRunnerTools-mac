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
            
            if !viewModel.recentWorkspaces.isEmpty {
                recentWorkspacesSection
            }
            Spacer()
            VStack(spacing: 10) {
                Button("Create Workspace From initial.pak") {
                    createWorkspace()
                }
                .buttonStyle(SRButtonStyle(colorStyle: .main, minWidth: 250))
                .disabled(viewModel.isBusy)

                Button("Open Existing Workspace") {
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

    private var recentWorkspacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Workspaces")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(viewModel.recentWorkspaces, id: \.standardizedFileURL.path) { workspace in
                    RecentWorkspaceRow(
                        workspace: workspace,
                        isDisabled: viewModel.isBusy,
                        open: { openRecentWorkspace(workspace) },
                        remove: { viewModel.removeRecentWorkspace(workspace) }
                    )
                }
            }
        }
        .frame(maxWidth: 420)
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

    private func openRecentWorkspace(_ workspace: URL) {
        Task {
            await viewModel.openWorkspace(workspace)
        }
    }
}

private struct RecentWorkspaceRow: View {
    let workspace: URL
    let isDisabled: Bool
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            openButton
            removeButton
        }
        .padding(10)
        .background(rowBackground)
        .overlay(rowBorder)
    }

    private var openButton: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.lastPathComponent)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(workspace.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isDisabled)
        .accessibilityLabel("Open \(workspace.lastPathComponent)")
    }

    private var removeButton: some View {
        Button(action: remove) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Remove \(workspace.lastPathComponent) from recent workspaces")
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(0.45))
    }
}

#Preview {
    LaunchWorkspaceView(viewModel: {
        let viewModel = WorkspaceViewModel()
        viewModel.recentWorkspaces = [
            URL(fileURLWithPath: "/Users/demo/SnowRunnerWorkspace", isDirectory: true),
            URL(fileURLWithPath: "/Users/demo/SnowRunnerMods/TestingWorkspace", isDirectory: true)
        ]
        return viewModel
    }())
        .frame(width: 880, height: 560)
}
