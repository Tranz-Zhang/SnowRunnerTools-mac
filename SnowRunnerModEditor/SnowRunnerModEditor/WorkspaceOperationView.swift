import SwiftUI
import SnowRunnerCore

public struct WorkspaceOperationView: View {
    @Bindable var viewModel: WorkspaceViewModel
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
            if let error = viewModel.errorMessage {
                errorSection(error)
            }
            buildSection
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Workspace Section
    
    private var workspaceSection: some View {
        panel {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.summary?.workspace.lastPathComponent ?? "Workspace")
                        .font(.headline)
                    Text(viewModel.summary?.workspace.path ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                HStack(spacing: 15) {
                    Button {
                        if let workspace = viewModel.summary?.workspace {
                            finder.reveal(workspace)
                        }
                    } label: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.gray)
                    }
                    .buttonStyle(SRButtonStyle(colorStyle: .normal, size: .small))
                    .help("Reveal")
                    .accessibilityLabel("Reveal Workspace")
                    
                    Button("Close Workspace") {
                        viewModel.closeWorkspace()
                    }
                    .buttonStyle(SRButtonStyle(colorStyle: .normal, size: .small, minWidth: 120))
                    .disabled(viewModel.isBusy)
                }
            }
        }
    }
    
    // MARK: Mod Section

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
                    .buttonStyle(SRButtonStyle(colorStyle: .main, size: .small, minWidth: 100))
                    .disabled(viewModel.isBusy)
                }

                Divider()

                if let mods = viewModel.summary?.mods, !mods.isEmpty {
                    ScrollView(.vertical) {
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
//                            GridRow {
//                                tableHeader("Enable")
//                                tableHeader("Name")
//                                Spacer()
//                                tableHeader("")
//                            }
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
    
    private var modCountText: String {
        let mods = viewModel.summary?.mods ?? []
        let active = mods.filter(\.enabled).count
        let disabled = mods.count - active
        return "\(active) active, \(disabled) disabled"
    }

    
    private func addMods() {
        let urls = panels.chooseModPaks()
        guard !urls.isEmpty else { return }
        Task { await viewModel.addMods(urls) }
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
            }.padding(.trailing, 20)
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

    
    // MARK: Quick Verify Section

    private var quickVerifySection: some View {
        panel {
            HStack(alignment: .center, spacing: 15) {
                if viewModel.busyState == .quickVerifying {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 5)
                        .padding(.leading, 2)
                } else {
                    Image(systemName: hasQuickVerifyConflicts ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(hasQuickVerifyConflicts ?  .red : .green)
                        .font(.system(size: 20))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Verify")
                        .font(.headline)
                    Text(quickVerifyText)
                        .font(.callout)
                        .foregroundStyle(hasQuickVerifyConflicts ? .red : .secondary)
                }
                Spacer()
                if hasAnyQuickVerifyConflicts {
                    Button("Show Conflict Details") {
                        viewModel.showConflictDetails()
                    }
                    .buttonStyle(SRButtonStyle(colorStyle: hasQuickVerifyConflicts ? .destructive : .normal, size: .small))
                }
            }
        }
    }
    
    private var hasQuickVerifyConflicts: Bool {
        (viewModel.quickVerifyResult?.unresolvedConflictCount ?? 0) > 0
    }

    private var hasAnyQuickVerifyConflicts: Bool {
        !(viewModel.quickVerifyResult?.conflicts.isEmpty ?? true)
    }

    private var quickVerifyText: String {
        guard let result = viewModel.quickVerifyResult else { return "Checking..." }
        if result.conflicts.isEmpty {
            return "No conflicts found"
        }
        if result.unresolvedConflictCount == 0 {
            return "All conflicts resolved"
        }
        return "\(result.unresolvedConflictCount) unresolved conflict\(result.unresolvedConflictCount == 1 ? "" : "s")"
    }

    // MARK: Build Section

    private var buildSection: some View {
        panel {
            HStack(spacing: 15) {
                if viewModel.busyState == .building {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 5)
                        .padding(.leading, 2)
                } else {
                    Image(systemName: viewModel.hasBuildOutput ? "archivebox.fill" : "archivebox")
                        .foregroundStyle(viewModel.hasBuildOutput ? .green : .gray)
                        .font(.system(size: 20))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build initial.pak")
                        .font(.headline)
//                    Text("build/initial.pak")
//                        .font(.callout.weight(.semibold))
                    if let lastBuildOutputDate = viewModel.lastBuildOutputDate {
                        Text("Last build: \(lastBuildOutputDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Found no build result")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    if viewModel.hasBuildOutput {
                        Button {
                            if let output = viewModel.summary?.buildOutput?.initialPak {
                                finder.reveal(output)
                            }
                        } label: {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(SRButtonStyle(colorStyle: .normal, size: .small))
                        .help("Reveal")
                        .accessibilityLabel("Reveal Build")
                    }
                    
                    Button("Build PAK") {
                        Task { await viewModel.build() }
                    }
                    .buttonStyle(SRButtonStyle(colorStyle: .main, size: .small, minWidth: 100))
                    .disabled(viewModel.isBusy)
                }
            }
        }
    }

    private func errorSection(_ error: String) -> some View {
        panel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 18))
                    .padding(.top, 2)
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

#Preview {
    WorkspaceOperationView(viewModel: WorkspaceOperationPreview.viewModel)
        .frame(width: 880, height: 560)
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
                targetArchive: .initial,
                internalName: "[media]\\classes\\trucks\\azov_64131.xml",
                targetPath: "[media]\\classes\\trucks\\azov_64131.xml",
                candidates: [
                    WorkspaceModConflictCandidate(modFolderName: "azov-tuning-pack", originalName: "classes/trucks/azov_64131.xml", byteSize: 2_048, sha256: "aaaaaaaaaaaa0000000000000000000000000000000000000000000000000000"),
                    WorkspaceModConflictCandidate(modFolderName: "loadstar-rescue-kit", originalName: "classes/trucks/azov_64131.xml", byteSize: 2_212, sha256: "bbbbbbbbbbbb0000000000000000000000000000000000000000000000000000")
                ]
            ),
            WorkspaceModConflict(
                targetArchive: .initial,
                internalName: "[media]\\classes\\wheels\\offroad.xml",
                targetPath: "[media]\\classes\\wheels\\offroad.xml",
                candidates: [
                    WorkspaceModConflictCandidate(modFolderName: "loadstar-rescue-kit", originalName: "classes/wheels/offroad.xml", byteSize: 1_024, sha256: "cccccccccccc0000000000000000000000000000000000000000000000000000"),
                    WorkspaceModConflictCandidate(modFolderName: "trail-wheel-pack", originalName: "classes/wheels/offroad.xml", byteSize: 1_080, sha256: "dddddddddddd0000000000000000000000000000000000000000000000000000")
                ],
                selectedMod: "trail-wheel-pack"
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
