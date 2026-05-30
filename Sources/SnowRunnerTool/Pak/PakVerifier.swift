import Foundation

public enum PakVerifier {
    private static let expectedDosTime: UInt16 = 0x1800
    private static let expectedDosDate: UInt16 = 0x0021
    private static let expectedVersionNeeded: UInt16 = 0x0014
    private static let expectedVersionMadeBy: UInt16 = 0x0314
    private static let expectedExternalAttributes: UInt32 = 0x81B60000
    private static let layoutSectionOrder = [
        "[media]\\classes",
        "[media]\\_dlc",
        "[media]\\_templates",
        "[ssl_cache]",
        "[strings]"
    ]

    public static func verifyBasic(_ archive: PakArchive) throws -> [VerifierIssue] {
        var issues: [VerifierIssue] = []

        if archive.isZip64 {
            issues.append(issue("zip64", "ZIP64 archives are not supported"))
        }

        if archive.localEntries.count != archive.entries.count {
            issues.append(issue("central-local-mismatch", "Central directory and local header counts differ"))
        }

        for entry in archive.entries {
            if let local = archive.localEntries.first(where: { $0.localHeaderOffset == entry.localHeaderOffset }) {
                if !headersAgree(central: entry, local: local) {
                    issues.append(issue("central-local-mismatch", "Central and local metadata differ for \(entry.name)"))
                }
            } else {
                issues.append(issue("central-local-mismatch", "Missing local header for \(entry.name)"))
            }

            if entry.generalPurposeBitFlag != 0 {
                issues.append(issue("unsupported-flag", "\(entry.name) has general-purpose bit flag \(entry.generalPurposeBitFlag)"))
            }
            if entry.generalPurposeBitFlag & 0x0008 != 0 {
                issues.append(issue("data-descriptor", "\(entry.name) uses a data descriptor"))
            }
            if entry.name.hasSuffix("/") || entry.name.hasSuffix("\\") {
                issues.append(issue("directory-entry", "\(entry.name) is a directory entry"))
            }
            if entry.compressionMethod != .stored && entry.compressionMethod != .deflated {
                issues.append(issue("invalid-method", "\(entry.name) has unsupported compression method \(entry.compressionMethod.rawValue)"))
            }
        }

        if let first = archive.entries.first {
            if first.name != "pak.load_list" {
                issues.append(issue("pak-load-list", "pak.load_list is not the first entry"))
            }
            if first.compressionMethod != .stored {
                issues.append(issue("pak-load-list", "pak.load_list must be stored"))
            }
        } else {
            issues.append(issue("pak-load-list", "Archive has no entries"))
        }

        let names = archive.entries.map(\.name)
        for namespace in ["[media]", "[strings]", "[ssl_cache]"] where !names.contains(where: { $0.hasPrefix(namespace) }) {
            issues.append(issue("missing-namespace", "Missing required namespace \(namespace)"))
        }

        do {
            try PakReader.validatePayloadCRCs(in: archive)
        } catch {
            issues.append(issue("crc-mismatch", String(describing: error)))
        }

        return issues
    }

    public static func verifyContentEquivalent(reference: PakArchive, candidate: PakArchive) throws -> [VerifierIssue] {
        var issues: [VerifierIssue] = []
        let referenceByName = Dictionary(uniqueKeysWithValues: reference.entries.map { ($0.name, $0) })
        let candidateByName = Dictionary(uniqueKeysWithValues: candidate.entries.map { ($0.name, $0) })
        let referenceNames = Set(referenceByName.keys)
        let candidateNames = Set(candidateByName.keys)

        for name in referenceNames.subtracting(candidateNames).sorted() {
            issues.append(issue("content-missing-entry", "Candidate is missing \(name)"))
        }
        for name in candidateNames.subtracting(referenceNames).sorted() {
            issues.append(issue("content-missing-entry", "Candidate has unexpected \(name)"))
        }

        for name in referenceNames.intersection(candidateNames).sorted() {
            guard let referenceEntry = referenceByName[name], let candidateEntry = candidateByName[name] else {
                continue
            }

            if referenceEntry.uncompressedSize != candidateEntry.uncompressedSize {
                issues.append(issue("content-size-mismatch", "\(name) uncompressed size differs"))
                continue
            }

            if referenceEntry.crc32 != candidateEntry.crc32 {
                issues.append(issue("content-crc-mismatch", "\(name) CRC differs"))
                continue
            }

            let referencePayload = try PakReader.readUncompressedPayload(entry: referenceEntry, in: reference)
            let candidatePayload = try PakReader.readUncompressedPayload(entry: candidateEntry, in: candidate)
            if referencePayload != candidatePayload {
                issues.append(issue("content-data-mismatch", "\(name) decompressed bytes differ"))
            }
        }

        return issues
    }

    public static func verifySnowPakLayout(_ archive: PakArchive) throws -> [VerifierIssue] {
        var issues = try verifyBasic(archive)

        for entry in archive.entries where entry.name != "pak.load_list" && entry.compressionMethod != .deflated {
            issues.append(issue("non-load-list-stored-entry", "\(entry.name) must be deflated"))
        }

        if !matchesSnowPakOrder(archive.entries) {
            issues.append(issue("entry-order", "Entries do not follow SnowPakTool-compatible layout"))
        }

        for entry in archive.entries {
            if entry.dosTime != expectedDosTime || entry.dosDate != expectedDosDate {
                issues.append(issue("invalid-timestamp", "\(entry.name) does not use 1980-01-01 03:00:00"))
            }
            if entry.localExtraFieldLength != 0 || entry.centralExtraFieldLength != 0 {
                issues.append(issue("extra-field", "\(entry.name) has an extra field"))
            }
            if entry.versionNeeded != expectedVersionNeeded {
                issues.append(issue("version-needed", "\(entry.name) version needed is \(entry.versionNeeded)"))
            }
            if entry.centralVersionMadeBy != expectedVersionMadeBy {
                issues.append(issue("version-made-by", "\(entry.name) version made by is \(entry.centralVersionMadeBy ?? 0)"))
            }
            if entry.centralExternalAttributes != expectedExternalAttributes {
                issues.append(issue("external-attributes", "\(entry.name) external attributes are \(entry.centralExternalAttributes ?? 0)"))
            }
            if entry.centralFileCommentLength != 0 {
                issues.append(issue("file-comment", "\(entry.name) has a file comment"))
            }
        }

        if archive.archiveCommentLength != 0 {
            issues.append(issue("archive-comment", "Archive has a comment"))
        }

        return issues
    }

    private static func headersAgree(central: PakEntry, local: PakEntry) -> Bool {
        central.name == local.name
            && central.compressionMethod == local.compressionMethod
            && central.generalPurposeBitFlag == local.generalPurposeBitFlag
            && central.crc32 == local.crc32
            && central.compressedSize == local.compressedSize
            && central.uncompressedSize == local.uncompressedSize
            && central.versionNeeded == local.versionNeeded
            && central.dosTime == local.dosTime
            && central.dosDate == local.dosDate
    }

    private static func matchesSnowPakOrder(_ entries: [PakEntry]) -> Bool {
        guard entries.count >= 2,
              entries[0].name == "pak.load_list",
              entries[1].name == "initial.cache_block"
        else {
            return false
        }

        var lastPosition = 1
        for prefix in layoutSectionOrder {
            guard let index = entries.firstIndex(where: { $0.name.hasPrefix(prefix) }) else {
                continue
            }
            if index < lastPosition {
                return false
            }
            lastPosition = index
        }

        return true
    }

    private static func issue(_ code: String, _ message: String) -> VerifierIssue {
        VerifierIssue(code: code, message: message)
    }
}
