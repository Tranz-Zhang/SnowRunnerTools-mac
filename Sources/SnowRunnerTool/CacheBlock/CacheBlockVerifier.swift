import Foundation

public enum CacheBlockVerifier {
    public static func verifyContentEquivalent(reference: CacheBlockArchive, candidate: CacheBlockArchive) throws -> [VerifierIssue] {
        var issues: [VerifierIssue] = []
        let referenceByName = Dictionary(uniqueKeysWithValues: reference.entries.map { ($0.internalName, $0) })
        let candidateByName = Dictionary(uniqueKeysWithValues: candidate.entries.map { ($0.internalName, $0) })
        let referenceNames = Set(referenceByName.keys)
        let candidateNames = Set(candidateByName.keys)

        for name in referenceNames.subtracting(candidateNames).sorted() {
            issues.append(VerifierIssue(code: "content-missing-entry", message: "Candidate is missing \(name)"))
        }
        for name in candidateNames.subtracting(referenceNames).sorted() {
            issues.append(VerifierIssue(code: "content-missing-entry", message: "Candidate has unexpected \(name)"))
        }

        for name in referenceNames.intersection(candidateNames).sorted() {
            guard let referenceEntry = referenceByName[name], let candidateEntry = candidateByName[name] else {
                continue
            }

            if referenceEntry.size != candidateEntry.size {
                issues.append(VerifierIssue(code: "content-size-mismatch", message: "\(name) size differs"))
                continue
            }

            let referencePayload = try CacheBlockReader.readPayload(entry: referenceEntry, in: reference)
            let candidatePayload = try CacheBlockReader.readPayload(entry: candidateEntry, in: candidate)
            if referencePayload != candidatePayload {
                issues.append(VerifierIssue(code: "content-data-mismatch", message: "\(name) payload differs"))
            }
        }

        return issues
    }
}
