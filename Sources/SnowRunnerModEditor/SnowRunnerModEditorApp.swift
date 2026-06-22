import SwiftUI

@main
struct SnowRunnerModEditorApp: App {
    @State private var viewModel = WorkspaceViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch viewModel.screen {
                case .launch:
                    LaunchWorkspaceView(viewModel: viewModel)
                case .workspace:
                    WorkspaceOperationView(viewModel: viewModel)
                case .conflictDetails:
                    ConflictDetailsView(viewModel: viewModel)
                }
            }
            .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.titleBar)
    }
}
