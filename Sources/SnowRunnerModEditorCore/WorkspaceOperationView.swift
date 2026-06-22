import SwiftUI
import SnowRunnerTool

public struct WorkspaceOperationView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var showingConflicts = false
    private let panels = AppFilePanels()
    private let finder = FinderActions()

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                workspaceSection
                modsSection
                quickVerifySection
                buildSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingConflicts) {
            ConflictDetailsView(conflicts: viewModel.quickVerifyResult?.conflicts ?? [])
                .frame(minWidth: 560, minHeight: 360)
        }
    }

    private var workspaceSection: some View {
        panel {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.summary?.workspace.lastPathComponent ?? "Workspace")
                        .font(.headline)
                    Text(viewModel.summary?.workspace.path ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Reveal Workspace") {
                    if let workspace = viewModel.summary?.workspace {
                        finder.reveal(workspace)
                    }
                }
                Button("Close Workspace") {
                    viewModel.closeWorkspace()
                }
                .disabled(viewModel.isBusy)
            }
        }
    }

    private var modsSection: some View {
        panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mods")
                            .font(.headline)
                        Text(modCountText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add Mods") {
                        addMods()
                    }
                    .disabled(viewModel.isBusy)
                }

                Divider()

                if let mods = viewModel.summary?.mods, !mods.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            tableHeader("Name")
                            tableHeader("Status")
                            tableHeader("Conflict")
                            tableHeader("Actions")
                        }
                        ForEach(mods) { mod in
                            GridRow {
                                Text(mod.folderName)
                                    .textSelection(.enabled)
                                Text(mod.enabled ? "Active" : "Disabled")
                                    .foregroundStyle(mod.enabled ? .green : .secondary)
                                Text(conflictCountText(for: mod.folderName))
                                    .foregroundStyle(hasConflict(mod.folderName) ? .red : .secondary)
                                HStack {
                                    Button("Reveal") {
                                        finder.reveal(mod.modDirectory)
                                    }
                                    if mod.enabled {
                                        Button("Disable") {
                                            Task { await viewModel.setModEnabled(folderName: mod.folderName, enabled: false) }
                                        }
                                        .disabled(viewModel.isBusy)
                                    } else {
                                        Button("Enable") {
                                            Task { await viewModel.setModEnabled(folderName: mod.folderName, enabled: true) }
                                        }
                                        .disabled(viewModel.isBusy)
                                    }
                                    Button("Remove", role: .destructive) {
                                        Task { await viewModel.removeMod(folderName: mod.folderName) }
                                    }
                                    .disabled(viewModel.isBusy)
                                }
                            }
                        }
                    }
                } else {
                    Text("No mods added.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quickVerifySection: some View {
        panel {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Verify")
                        .font(.headline)
                    Text(quickVerifyText)
                        .font(.callout)
                        .foregroundStyle(hasQuickVerifyConflicts ? .red : .secondary)
                    Text("Checks duplicate mapped targets between enabled mods. Mod-over-initial replacements are ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.busyState == .quickVerifying {
                    ProgressView()
                }
                if hasQuickVerifyConflicts {
                    Button("Show Conflict Details") {
                        showingConflicts = true
                    }
                }
            }
        }
    }

    private var buildSection: some View {
        panel {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build Output")
                        .font(.headline)
                    Text("build/initial.pak")
                        .font(.callout.weight(.semibold))
                    Text("Full verification runs before publishing build/initial.pak and workspace-build-report.md.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Build PAK") {
                    Task { await viewModel.build() }
                }
                .disabled(viewModel.isBusy)
                Button("Review Build") {
                    if let output = viewModel.summary?.buildInitialPak {
                        finder.reveal(output)
                    }
                }
                .disabled(viewModel.summary == nil || viewModel.buildResult == nil)
            }
        }
    }

    private var modCountText: String {
        let mods = viewModel.summary?.mods ?? []
        let active = mods.filter(\.enabled).count
        let disabled = mods.count - active
        return "\(active) active, \(disabled) disabled"
    }

    private var hasQuickVerifyConflicts: Bool {
        !(viewModel.quickVerifyResult?.conflicts.isEmpty ?? true)
    }

    private var quickVerifyText: String {
        guard let result = viewModel.quickVerifyResult else { return "Checking..." }
        return result.conflicts.isEmpty ? "No conflicts found" : "Conflicts found"
    }

    private func addMods() {
        let urls = panels.chooseModPaks()
        guard !urls.isEmpty else { return }
        Task { await viewModel.addMods(urls) }
    }

    private func hasConflict(_ folderName: String) -> Bool {
        (viewModel.quickVerifyResult?.conflicts ?? []).contains { $0.mods.contains(folderName) }
    }

    private func conflictCountText(for folderName: String) -> String {
        let count = (viewModel.quickVerifyResult?.conflicts ?? []).filter { $0.mods.contains(folderName) }.count
        return count == 0 ? "None" : "\(count) target\(count == 1 ? "" : "s")"
    }

    private func tableHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator)
            }
    }
}

private struct ConflictDetailsView: View {
    let conflicts: [WorkspaceModConflict]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conflict Details")
                .font(.title3.weight(.semibold))
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
        .padding(20)
    }
}
