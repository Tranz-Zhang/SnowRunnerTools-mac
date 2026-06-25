import AppKit
import UniformTypeIdentifiers

@MainActor
struct AppFilePanels {
    func chooseInitialPak() -> URL? {
        chooseFile(title: "Choose initial.pak", allowedExtensions: ["pak"])
    }

    func chooseWorkspaceFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Workspace Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseModPaks() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Choose Mod Packages"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["pak", "zip"].compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.urls : []
    }

    private func chooseFile(title: String, allowedExtensions: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
