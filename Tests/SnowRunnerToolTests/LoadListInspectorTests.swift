import XCTest
@testable import SnowRunnerTool

final class LoadListInspectorTests: XCTestCase {
    func testCompactReportShapeAgainstReferenceManifest() throws {
        let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
        let manifest = try LoadListReader.readManifest(from: url)

        let report = LoadListInspector.compactReport(manifest)
        XCTAssertTrue(report.hasSuffix("\n"))
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        XCTAssertEqual(lines.count, 17917)

        XCTAssertEqual(lines.first, "--Start--")
        XCTAssertEqual(lines.last, "--End--")
        XCTAssertTrue(lines.contains("SSL_INITIAL load"))
        XCTAssertTrue(lines.contains("sound.sound_list"))
    }

    func testCompactReportMatchesSnowPakToolReferenceReportWhenAvailable() throws {
        guard let oracleURL = TestFixtures.optionalCompactReferenceReport() else {
            throw XCTSkip("fixtures/reports/load-list-compact.txt is not present (Windows-only oracle).")
        }
        let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
        let manifest = try LoadListReader.readManifest(from: url)

        let actual = LoadListInspector.compactReport(manifest)
        let expected = try String(contentsOf: oracleURL, encoding: .utf8)

        XCTAssertEqual(normalizedLines(actual), normalizedLines(expected))
    }

    private func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .drop(while: { $0.isEmpty })
            .reversed()
            .drop(while: { $0.isEmpty })
            .reversed()
            .map { String($0) }
    }
}
