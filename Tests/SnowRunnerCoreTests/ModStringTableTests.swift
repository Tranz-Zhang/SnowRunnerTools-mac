import Foundation
import XCTest
@testable import SnowRunnerCore

final class ModStringTableTests: XCTestCase {
    func testMergePreservesBaseOnlyRowsAndReplacesModKeyGroups() throws {
        let base = stringTableData("""
        BASE_KEY\t\t"Base"
        DUP_KEY\t\t"Old 1"
        KEEP_KEY\t\t"Keep"
        DUP_KEY\t\t"Old 2"
        """)
        let mod = stringTableData("""
        DUP_KEY\t\t"New 1"
        DUP_KEY\t\t"New 2"
        NEW_KEY\t\t"New"
        """)

        let merged = try ModStringTable.merge(
            baseData: base,
            modData: mod,
            path: "[strings]\\strings_english.str"
        )

        XCTAssertEqual(decodedStringTable(merged), """
        BASE_KEY\t\t"Base"
        KEEP_KEY\t\t"Keep"
        DUP_KEY\t\t"New 1"
        DUP_KEY\t\t"New 2"
        NEW_KEY\t\t"New"
        """)
    }

    func testMergeRejectsMalformedNonEmptyRows() throws {
        let base = stringTableData("BASE_KEY\t\t\"Base\"\n")
        let mod = stringTableData("MALFORMED ROW\n")

        XCTAssertThrowsError(try ModStringTable.merge(
            baseData: base,
            modData: mod,
            path: "[strings]\\strings_english.str"
        )) { error in
            guard case let ModMergeError.invalidStringTable(path, reason) = error else {
                XCTFail("expected invalidStringTable, got \(error)")
                return
            }
            XCTAssertEqual(path, "[strings]\\strings_english.str")
            XCTAssertTrue(reason.contains("line 1"))
        }
    }
}

func stringTableData(_ rows: String) -> Data {
    let normalized = rows
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .joined(separator: "\r\n")
    return normalized.data(using: .utf16)!
}

func decodedStringTable(_ data: Data) -> String {
    String(data: data, encoding: .utf16)!
        .replacingOccurrences(of: "\r\n", with: "\n")
}
