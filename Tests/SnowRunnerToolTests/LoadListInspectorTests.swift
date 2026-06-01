import XCTest
@testable import SnowRunnerTool

final class LoadListInspectorTests: XCTestCase {
    func testCompactReportShapeAgainstReferenceManifest() throws {
        let url = try TestFixtures.extractPakLoadList(from: TestFixtures.initialPak)
        let manifest = try LoadListReader.readManifest(from: url)

        let report = LoadListInspector.compactReport(manifest)
        XCTAssertTrue(report.hasSuffix("\n"))
        let lines = report.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        XCTAssertEqual(lines.count, 17902)

        let expectedColumnsPerLine = 4
        for line in lines {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            XCTAssertEqual(columns.count, expectedColumnsPerLine, "line did not have \(expectedColumnsPerLine) tab-separated columns: \(line)")
        }

        // First record across phases must be from the SSL_INITIAL phase (the
        // reference fixture's first non-empty phase).
        XCTAssertTrue(lines.first?.hasPrefix("SSL_INITIAL load\t") ?? false)
        XCTAssertTrue(lines.last?.hasPrefix("SOUND load\t") ?? false)
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
        text
            .split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .drop(while: { $0.isEmpty })
            .reversed()
            .drop(while: { $0.isEmpty })
            .reversed()
            .map { String($0) }
    }
}
