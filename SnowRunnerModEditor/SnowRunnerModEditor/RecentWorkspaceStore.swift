import Foundation

@MainActor
public protocol RecentWorkspaceStoring {
    func load() -> [URL]
    func record(_ workspace: URL)
    func remove(_ workspace: URL)
    func startAccessing(_ workspace: URL) -> RecentWorkspaceAccess
}

public struct RecentWorkspaceAccess {
    public let url: URL
    private let stopAccessing: () -> Void

    init(url: URL, stopAccessing: @escaping () -> Void) {
        self.url = url
        self.stopAccessing = stopAccessing
    }

    public func stop() {
        stopAccessing()
    }
}

public struct RecentWorkspaceStore: RecentWorkspaceStoring {
    public static let defaultKey = "recentWorkspaces"

    private let userDefaults: UserDefaults
    private let key: String
    private let limit: Int

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = Self.defaultKey,
        limit: Int = 8
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.limit = limit
    }

    public func load() -> [URL] {
        loadEntries().map(\.url)
    }

    public func record(_ workspace: URL) {
        let standardized = workspace.standardizedFileURL
        guard let entry = StoredWorkspace(url: standardized) else { return }
        let updated = [entry] + loadEntries().filter {
            $0.url.standardizedFileURL.path != standardized.path
        }
        save(Array(updated.prefix(limit)))
    }

    public func remove(_ workspace: URL) {
        let standardized = workspace.standardizedFileURL
        save(loadEntries().filter { $0.url.standardizedFileURL.path != standardized.path })
    }

    public func startAccessing(_ workspace: URL) -> RecentWorkspaceAccess {
        let accessibleWorkspace = resolvedWorkspace(matching: workspace) ?? workspace.standardizedFileURL
        let didStartAccess = accessibleWorkspace.startAccessingSecurityScopedResource()
        return RecentWorkspaceAccess(url: accessibleWorkspace) {
            if didStartAccess {
                accessibleWorkspace.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func loadEntries() -> [StoredWorkspace] {
        guard let data = userDefaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([StoredWorkspace].self, from: data)
        else { return [] }
        return entries
    }

    private func resolvedWorkspace(matching workspace: URL) -> URL? {
        let path = workspace.standardizedFileURL.path
        return loadEntries()
            .first { $0.url.standardizedFileURL.path == path }?
            .resolvedURL
    }

    private func save(_ workspaces: [StoredWorkspace]) {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        userDefaults.set(data, forKey: key)
    }
}

private struct StoredWorkspace: Codable {
    var path: String
    var bookmarkData: Data

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    var resolvedURL: URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    init?(url: URL) {
        let standardized = url.standardizedFileURL
        guard let bookmarkData = try? standardized.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }
        self.path = standardized.path
        self.bookmarkData = bookmarkData
    }
}
