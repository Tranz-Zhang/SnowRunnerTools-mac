import Foundation

public enum ModStringTable {
    public static func merge(baseData: Data, modData: Data, path: String) throws -> Data {
        let baseRows = try parseRows(baseData, path: path)
        let modRows = try parseRows(modData, path: path)
        let modKeys = Set(modRows.map(\.key))
        let mergedRows = baseRows.filter { !modKeys.contains($0.key) } + modRows
        let text = mergedRows.map(\.body).joined(separator: "\r\n")
        guard let data = text.data(using: .utf16) else {
            throw ModMergeError.invalidStringTable(path: path, reason: "could not encode merged UTF-16 data")
        }
        return data
    }

    private struct Row {
        let key: String
        let body: String
    }

    private static func parseRows(_ data: Data, path: String) throws -> [Row] {
        guard let text = String(data: data, encoding: .utf16) else {
            throw ModMergeError.invalidStringTable(path: path, reason: "could not decode UTF-16 data")
        }

        var rows: [Row] = []
        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingPrefix("\u{feff}")
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            guard let tabIndex = line.firstIndex(of: "\t") else {
                throw ModMergeError.invalidStringTable(
                    path: path,
                    reason: "line \(lineNumber) is missing a tab separator"
                )
            }
            let key = String(line[..<tabIndex])
            guard !key.isEmpty else {
                throw ModMergeError.invalidStringTable(
                    path: path,
                    reason: "line \(lineNumber) has an empty key"
                )
            }
            rows.append(Row(key: key, body: line))
        }
        return rows
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
