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
        VStack(alignment: .leading, spacing: 16) {
            workspaceSection
            modsSection
                .layoutPriority(1)
            quickVerifySection
            buildSection
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                .buttonStyle(LaunchActionButtonStyle(size: .small))
                Button("Close Workspace") {
                    viewModel.closeWorkspace()
                }
                .buttonStyle(LaunchActionButtonStyle(size: .small))
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
                    .buttonStyle(LaunchActionButtonStyle(colorStyle: .main, size: .small))
                    .disabled(viewModel.isBusy)
                }

                Divider()

                if let mods = viewModel.summary?.mods, !mods.isEmpty {
                    ScrollView(.vertical) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                            GridRow {
                                tableHeader("Enable")
                                tableHeader("Name")
                                Spacer()
                                tableHeader("")
                            }
                            ForEach(mods) { mod in
                                modRow(mod)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Text("No mods added.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    .buttonStyle(LaunchActionButtonStyle(size: .small))
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
                .buttonStyle(LaunchActionButtonStyle(colorStyle: .main, size: .small))
                .disabled(viewModel.isBusy)
                Button("Review Build") {
                    if let output = viewModel.summary?.buildInitialPak {
                        finder.reveal(output)
                    }
                }
                .buttonStyle(LaunchActionButtonStyle(size: .small))
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

    private func tableHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func modRow(_ mod: PakWorkspaceModSummary) -> some View {
        GridRow {
            Toggle("Enabled", isOn: modEnabledBinding(for: mod))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(viewModel.isBusy)
                .accessibilityLabel("Enable \(mod.folderName)")
            Text(mod.folderName)
                .font(.system(size: 15, weight: .regular))
                .textSelection(.enabled)
            Spacer()
            HStack(spacing: 15) {
                Button {
                    finder.reveal(mod.modDirectory)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal")
                .accessibilityLabel("Reveal \(mod.folderName)")
                
                Button(role: .destructive) {
                    Task { await viewModel.removeMod(folderName: mod.folderName) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isBusy)
                .help("Remove")
                .accessibilityLabel("Remove \(mod.folderName)")
            }
        }.frame(height: 30)
    }

    private func modEnabledBinding(for mod: PakWorkspaceModSummary) -> Binding<Bool> {
        Binding(
            get: { mod.enabled },
            set: { enabled in
                Task { await viewModel.setModEnabled(folderName: mod.folderName, enabled: enabled) }
            }
        )
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
    @Environment(\.dismiss) private var dismiss
    let conflicts: [WorkspaceModConflict]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conflict Details")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
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

#Preview {
    WorkspaceOperationView(viewModel: WorkspaceOperationPreview.viewModel)
        .frame(width: 900, height: 640)
}

private enum WorkspaceOperationPreview {
    @MainActor
    static var viewModel: WorkspaceViewModel {
        let workspace = URL(fileURLWithPath: "/Users/demo/SnowRunnerWorkspace", isDirectory: true)
        let model = WorkspaceViewModel()
        model.screen = .workspace
        model.summary = PakWorkspaceSummary(
            workspace: workspace,
            initialSourcePath: "/Applications/SnowRunner/preload/paks/client/initial.pak",
            mods: [
                modSummary(folderName: "azov-tuning-pack", archiveName: "azov_tuning.pak", workspace: workspace, enabled: true),
                modSummary(folderName: "loadstar-rescue-kit", archiveName: "loadstar_rescue.pak", workspace: workspace, enabled: true),
                modSummary(folderName: "old-truck-addon", archiveName: "old_truck_addon.pak", workspace: workspace, enabled: false)
            ],
            buildInitialPak: workspace.appendingPathComponent("build/initial.pak"),
            buildReport: workspace.appendingPathComponent("build/workspace-build-report.md")
        )
        model.quickVerifyResult = WorkspaceQuickVerifyResult(conflicts: [
            WorkspaceModConflict(
                targetPath: "initial.pak/classes/trucks/azov_64131.xml",
                mods: ["azov-tuning-pack", "loadstar-rescue-kit"]
            )
        ])
        return model
    }

    private static func modSummary(
        folderName: String,
        archiveName: String,
        workspace: URL,
        enabled: Bool
    ) -> PakWorkspaceModSummary {
        PakWorkspaceModSummary(
            folderName: folderName,
            archiveName: archiveName,
            sourcePath: "/Users/demo/Downloads/\(archiveName)",
            modDirectory: workspace.appendingPathComponent("mods/\(folderName)", isDirectory: true),
            sourceCache: workspace.appendingPathComponent(".snowrunner/sources/\(archiveName)"),
            enabled: enabled
        )
    }
}
