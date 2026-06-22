import SwiftUI

public struct LaunchWorkspaceView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Workspace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Choose a SnowRunner workspace")
                    .font(.title2.weight(.semibold))
                Text("Create one from initial.pak or open a folder containing .snowrunner-workspace.json.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Create Workspace From initial.pak") {}
            Button("Open Existing Workspace Folder") {}
            Text("Opening fails if the selected folder is not a valid workspace.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
