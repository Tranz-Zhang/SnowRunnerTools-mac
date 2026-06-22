import SwiftUI
import SnowRunnerModEditorCore

@main
struct SnowRunnerModEditorApp: App {
    var body: some Scene {
        WindowGroup {
            LaunchWorkspaceView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.titleBar)
    }
}
