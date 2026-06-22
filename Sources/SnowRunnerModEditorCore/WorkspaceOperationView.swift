import SwiftUI

public struct WorkspaceOperationView: View {
    @Bindable var viewModel: WorkspaceViewModel

    public init(viewModel: WorkspaceViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Workspace", subtitle: viewModel.summary?.workspace.path ?? "No workspace loaded")
                SectionHeader(title: "Mods", subtitle: "No mods")
                SectionHeader(title: "Quick Verify", subtitle: "Not run")
                SectionHeader(title: "Build Output", subtitle: "build/initial.pak")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator)
        }
    }
}
