import SwiftUI
import SnowRunnerModEditorCore

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
                }
            }
            .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.titleBar)
    }
}
