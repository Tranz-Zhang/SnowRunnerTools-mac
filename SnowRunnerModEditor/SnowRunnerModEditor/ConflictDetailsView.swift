import SwiftUI
import SnowRunnerCore

public struct ConflictDetailsView: View {
    @Bindable var viewModel: WorkspaceViewModel
    @State private var selectedConflictID: String?

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if conflicts.isEmpty {
                Text("No conflicts found.")
                    .foregroundStyle(.secondary)
            } else {
                HSplitView {
                    List(conflicts, selection: $selectedConflictID) { conflict in
                        conflictRow(conflict)
                            .tag(conflict.id)
                    }
                    .frame(minWidth: 260, idealWidth: 320)

                    if let conflict = selectedConflict {
                        conflictDetail(conflict)
                            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        Text("Select a conflict.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectedConflictID = selectedConflictID ?? conflicts.first?.id
        }
        .onChange(of: conflicts.map(\.id)) { _, ids in
            if let selectedConflictID, ids.contains(selectedConflictID) {
                return
            }
            selectedConflictID = ids.first
        }
    }

    private var conflicts: [WorkspaceModConflict] {
        viewModel.quickVerifyResult?.conflicts ?? []
    }

    private var selectedConflict: WorkspaceModConflict? {
        conflicts.first { $0.id == selectedConflictID }
    }

    private var header: some View {
        HStack {
            Text("Conflict Details")
                .font(.title3.weight(.semibold))
            Spacer()
            Button("Back to Workspace") {
                viewModel.showWorkspace()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private func conflictRow(_ conflict: WorkspaceModConflict) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(conflict.isResolved ? "Resolved" : "Unresolved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(conflict.isResolved ? .green : .red)
                Spacer()
            }
            Text(conflict.targetPath)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .textSelection(.enabled)
            Text(conflict.mods.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private func conflictDetail(_ conflict: WorkspaceModConflict) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(conflict.targetPath)
                    .font(.headline)
                    .textSelection(.enabled)

                HStack {
                    Text(conflict.isResolved ? "Resolved by \(conflict.selectedMod ?? "")" : "Choose a version")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(conflict.isResolved ? .green : .primary)
                    Spacer()
                    if conflict.isResolved {
                        Button("Clear Resolution") {
                            Task {
                                await viewModel.clearConflictResolution(
                                    targetArchive: conflict.targetArchive,
                                    internalName: conflict.internalName
                                )
                            }
                        }
                        .buttonStyle(SRButtonStyle(colorStyle: .normal, size: .small))
                        .disabled(viewModel.isBusy)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(conflict.candidates) { candidate in
                        candidateRow(candidate, conflict: conflict)
                    }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
        }
    }

    private func candidateRow(
        _ candidate: WorkspaceModConflictCandidate,
        conflict: WorkspaceModConflict
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(candidate.modFolderName)
                        .font(.callout.weight(.semibold))
                    if conflict.selectedMod == candidate.modFolderName {
                        Text("Selected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                Text(candidate.originalName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("\(candidate.byteSize) bytes · \(candidate.sha256.prefix(12))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(conflict.isByteIdentical ? "Keep One Copy" : "Use This Version") {
                Task {
                    await viewModel.resolveConflict(
                        targetArchive: conflict.targetArchive,
                        internalName: conflict.internalName,
                        selectedMod: candidate.modFolderName
                    )
                }
            }
            .buttonStyle(SRButtonStyle(colorStyle: .main, size: .small))
            .disabled(viewModel.isBusy || conflict.selectedMod == candidate.modFolderName)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(conflict.selectedMod == candidate.modFolderName ? Color.green.opacity(0.6) : Color.gray.opacity(0.2))
        }
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
                    WorkspaceModConflictCandidate(modFolderName: "trail-wheel-pack", originalName: "classes/wheels/offroad.xml", byteSize: 1_024, sha256: "cccccccccccc0000000000000000000000000000000000000000000000000000")
                ],
                selectedMod: "trail-wheel-pack"
            )
        ])
        return model
    }
}
