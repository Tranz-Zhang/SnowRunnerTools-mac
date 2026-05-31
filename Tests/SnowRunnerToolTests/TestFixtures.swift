import Foundation

enum TestFixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let initialPak = root.appendingPathComponent("fixtures/initial.pak")
    static let initialRepackedPak = root.appendingPathComponent("fixtures/initial.repacked.pak")
}

func temporaryDirectory(named name: String) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnowRunnerToolTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
    return base
}

func writeFile(root: URL, relativePath: String, data: Data) throws {
    let fileURL = relativePath
        .split(separator: "/")
        .reduce(root) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }
    try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try data.write(to: fileURL)
}
