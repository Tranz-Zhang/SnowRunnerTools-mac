import Foundation
@testable import SnowRunnerModEditor
import XCTest

final class RecentWorkspaceStoreTests: XCTestCase {
    private var suiteName: String!
    private var userDefaults: UserDefaults!
    private var workspaceRoot: URL!

    override func setUp() {
        super.setUp()
        suiteName = "RecentWorkspaceStoreTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentWorkspaceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workspaceRoot)
        userDefaults.removePersistentDomain(forName: suiteName)
        workspaceRoot = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    func testRecordStoresMostRecentWorkspaceFirst() {
        let store = RecentWorkspaceStore(userDefaults: userDefaults)
        let first = workspaceURL("first")
        let second = workspaceURL("second")

        store.record(first)
        store.record(second)

        XCTAssertEqual(store.load(), [second, first])
    }

    @MainActor
    func testRecordDeduplicatesStandardizedPathsAndMovesExistingItemToFront() {
        let store = RecentWorkspaceStore(userDefaults: userDefaults)
        let original = workspaceURL("demo")
        let duplicate = workspaceRoot
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent(workspaceRoot.lastPathComponent, isDirectory: true)
            .appendingPathComponent("demo", isDirectory: true)
        let other = workspaceURL("other")

        store.record(original)
        store.record(other)
        store.record(duplicate)

        XCTAssertEqual(store.load(), [original.standardizedFileURL, other])
    }

    @MainActor
    func testRecordKeepsOnlyEightMostRecentWorkspaces() {
        let store = RecentWorkspaceStore(userDefaults: userDefaults)
        let workspaces = (1...10).map { workspaceURL("workspace-\($0)") }

        for workspace in workspaces {
            store.record(workspace)
        }

        XCTAssertEqual(store.load(), Array(workspaces.reversed().prefix(8)))
    }

    @MainActor
    func testRemoveDeletesMatchingStandardizedPath() {
        let store = RecentWorkspaceStore(userDefaults: userDefaults)
        let first = workspaceURL("first")
        let second = workspaceURL("second")
        let secondEquivalent = workspaceRoot
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent(workspaceRoot.lastPathComponent, isDirectory: true)
            .appendingPathComponent("second", isDirectory: true)
        store.record(first)
        store.record(second)

        store.remove(secondEquivalent)

        XCTAssertEqual(store.load(), [first])
    }

    private func workspaceURL(_ name: String) -> URL {
        let url = workspaceRoot.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
