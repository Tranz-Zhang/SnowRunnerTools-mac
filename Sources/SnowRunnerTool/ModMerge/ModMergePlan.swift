import Foundation

public struct ModMergePlan: Equatable {
    public let baseEntryCount: Int
    public let mappedModEntryCount: Int
    public let netNewOuterPakEntryCount: Int
    public let collisions: [String]
    public let duplicateIdenticalMappedNames: [String]
    public let loadListSourceOverrides: [ModLoadListSourceOverride]
    public let loadListCandidateRecords: [LoadListRecord]
    public let netNewLoadListRecordCount: Int
}

public struct ModMergeResult: Equatable {
    public let plan: ModMergePlan
    public let outputURL: URL?
    public let writtenEntryCount: Int?
}

public struct ModMergeOptions: Equatable {
    public let allowOverwrite: Bool
    public let dryRun: Bool
    public let reportURL: URL?

    public init(allowOverwrite: Bool, dryRun: Bool = false, reportURL: URL? = nil) {
        self.allowOverwrite = allowOverwrite
        self.dryRun = dryRun
        self.reportURL = reportURL
    }
}
