import Foundation

public struct ModMergePlan: Equatable {
    public let baseEntryCount: Int
    public let mappedModEntryCount: Int
    public let netNewOuterPakEntryCount: Int
    public let collisions: [String]
    public let textureBaseEntryCount: Int
    public let netNewTexturePakEntryCount: Int
    public let textureCollisions: [String]
    public let duplicateIdenticalMappedNames: [String]
    public let loadListSourceOverrides: [ModLoadListSourceOverride]
    public let loadListCandidateRecords: [LoadListRecord]
    public let netNewLoadListRecordCount: Int

    public var textureLoadListRecordCount: Int {
        loadListCandidateRecords.filter {
            $0.manifestPath.hasPrefix("<textures>\\")
                && $0.loaderType == "texture_loader"
                && $0.sourcePak == "shared_textures_base.pak"
        }.count
    }
}

public struct ModMergeResult: Equatable {
    public let plan: ModMergePlan
    public let outputURL: URL?
    public let outputTexturesURL: URL?
    public let writtenEntryCount: Int?
    public let writtenTextureEntryCount: Int?
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
