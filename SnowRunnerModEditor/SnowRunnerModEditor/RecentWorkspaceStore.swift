import Foundation

public protocol RecentWorkspaceStoring {
    func load() -> [URL]
    func record(_ workspace: URL)
    func remove(_ workspace: URL)
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
        userDefaults.stringArray(forKey: key)?.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? []
    }

    public func record(_ workspace: URL) {
        let standardized = workspace.standardizedFileURL
        let updated = [standardized] + load().filter {
            $0.standardizedFileURL.path != standardized.path
        }
        save(Array(updated.prefix(limit)))
    }

    public func remove(_ workspace: URL) {
        let standardized = workspace.standardizedFileURL
        save(load().filter { $0.standardizedFileURL.path != standardized.path })
    }

    private func save(_ workspaces: [URL]) {
        userDefaults.set(
            workspaces.map { $0.standardizedFileURL.path },
            forKey: key
        )
    }
}
