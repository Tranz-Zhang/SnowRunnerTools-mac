import Foundation

public struct ModReferenceIssue: Equatable, Sendable {
    public let sourcePath: String
    public let referencedCategory: String
    public let missingValue: String
    public let explanation: String

    public init(sourcePath: String, referencedCategory: String, missingValue: String, explanation: String) {
        self.sourcePath = sourcePath
        self.referencedCategory = referencedCategory
        self.missingValue = missingValue
        self.explanation = explanation
    }
}

public enum ModReferenceValidator {
    public static func validateInitialSources(_ sources: [PakFileSource]) throws {
        try validateInitialSources(sources, validateClassLocalReferences: true, parseXML: parseXMLDocument(data:path:))
    }

    static func validateInitialSources(
        _ sources: [PakFileSource],
        validateClassLocalReferences: Bool
    ) throws {
        try validateInitialSources(
            sources,
            validateClassLocalReferences: validateClassLocalReferences,
            parseXML: parseXMLDocument(data:path:)
        )
    }

    static func validateInitialSources(
        _ sources: [PakFileSource],
        validateClassLocalReferences: Bool = true,
        parseXML: (Data, String) throws -> XMLDocument
    ) throws {
        var parsedSources: [ParsedSource] = []
        parsedSources.reserveCapacity(sources.count)
        var indexes = ReferenceIndexes()

        for source in sources where isTruckClassPath(source.internalName) {
            indexes.classBasenames.insert(fileBasename(source.internalName))
        }

        for source in sources where isReferenceValidationXMLPath(source.internalName) {
            let data = try source.readData()
            let document = try parseXML(data, source.internalName)
            guard let root = document.rootElement() else {
                continue
            }
            let parsed = ParsedSource(path: source.internalName, root: root)
            parsedSources.append(parsed)

            let basename = fileBasename(source.internalName)
            if isWheelRegistryPath(source.internalName) {
                if let parent = registryParentBasename(from: root) {
                    indexes.wheelParents[basename] = parent
                }
                mergeWheelRegistry(from: root, basename: basename, into: &indexes)
            } else if isEngineRegistryPath(source.internalName) {
                if let parent = registryParentBasename(from: root) {
                    indexes.engineParents[basename] = parent
                }
                mergeNamedRegistry(from: root, registryRootName: "EngineVariants", childName: "Engine", basename: basename, into: &indexes.enginesByRegistry)
            } else if isGearboxRegistryPath(source.internalName) {
                if let parent = registryParentBasename(from: root) {
                    indexes.gearboxParents[basename] = parent
                }
                mergeNamedRegistry(from: root, registryRootName: "GearboxVariants", childName: "Gearbox", basename: basename, into: &indexes.gearboxesByRegistry)
            } else if isSuspensionRegistryPath(source.internalName) {
                if let parent = registryParentBasename(from: root) {
                    indexes.suspensionParents[basename] = parent
                }
                mergeNamedRegistry(from: root, registryRootName: "SuspensionSetVariants", childName: "SuspensionSet", basename: basename, into: &indexes.suspensionsByRegistry)
            } else if isWinchRegistryPath(source.internalName) {
                if let parent = registryParentBasename(from: root) {
                    indexes.winchParents[basename] = parent
                }
                mergeNamedRegistry(from: root, registryRootName: "WinchVariants", childName: "Winch", basename: basename, into: &indexes.winchesByRegistry)
            }
        }

        resolveRegistryInheritance(in: &indexes)

        var issues: [ModReferenceIssue] = []
        for parsed in parsedSources where isTruckClassPath(parsed.path) {
            if validateClassLocalReferences {
                validateParentReferences(in: parsed, indexes: indexes, issues: &issues)
                validateDefaultAddonReferences(in: parsed, indexes: indexes, issues: &issues)
            }
            validateWheelReferences(in: parsed, indexes: indexes, issues: &issues)
            validateUpgradeSocket(
                in: parsed,
                socketName: "EngineSocket",
                category: "engine",
                registries: indexes.enginesByRegistry,
                issues: &issues
            )
            validateUpgradeSocket(
                in: parsed,
                socketName: "GearboxSocket",
                category: "gearbox",
                registries: indexes.gearboxesByRegistry,
                issues: &issues
            )
            validateUpgradeSocket(
                in: parsed,
                socketName: "SuspensionSocket",
                category: "suspension",
                registries: indexes.suspensionsByRegistry,
                issues: &issues
            )
            validateUpgradeSocket(
                in: parsed,
                socketName: "WinchUpgradeSocket",
                category: "winch",
                registries: indexes.winchesByRegistry,
                issues: &issues
            )
        }

        if !issues.isEmpty {
            throw ModMergeError.brokenMergedReferences(issues)
        }
    }

    private struct ParsedSource {
        let path: String
        let root: XMLElement
    }

    private struct WheelRegistry {
        var tires: Set<String> = []
        var rims: Set<String> = []
    }

    private struct ReferenceIndexes {
        var classBasenames: Set<String> = []
        var wheelsByRegistry: [String: WheelRegistry] = [:]
        var wheelParents: [String: String] = [:]
        var enginesByRegistry: [String: Set<String>] = [:]
        var engineParents: [String: String] = [:]
        var gearboxesByRegistry: [String: Set<String>] = [:]
        var gearboxParents: [String: String] = [:]
        var suspensionsByRegistry: [String: Set<String>] = [:]
        var suspensionParents: [String: String] = [:]
        var winchesByRegistry: [String: Set<String>] = [:]
        var winchParents: [String: String] = [:]
    }

    private static func parseXMLDocument(data: Data, path: String) throws -> XMLDocument {
        do {
            return try XMLDocument(data: data, options: [])
        } catch {
            guard let text = String(data: data, encoding: .utf8) else {
                throw ModMergeError.invalidRegistryXML(path: path, reason: "XML is not UTF-8")
            }
            return try parseWrappedXMLText(text, path: path)
        }
    }

    private static func parseWrappedXMLText(_ text: String, path: String) throws -> XMLDocument {
        do {
            return try parseWrappedXMLTextWithoutRepair(text)
        } catch {
            let repaired = repairXMLForParsing(text)
            guard repaired != text else {
                throw ModMergeError.invalidRegistryXML(path: path, reason: "could not parse XML: \(error)")
            }
            do {
                return try parseWrappedXMLTextWithoutRepair(repaired)
            } catch {
                throw ModMergeError.invalidRegistryXML(path: path, reason: "could not parse XML: \(error)")
            }
        }
    }

    private static func parseWrappedXMLTextWithoutRepair(_ text: String) throws -> XMLDocument {
        let wrapped = "<_ModReferenceValidatorRoot>\n\(text)\n</_ModReferenceValidatorRoot>"
        return try XMLDocument(data: Data(wrapped.utf8), options: [])
    }

    private static let namespaceLikeAttributeRegex = try! NSRegularExpression(
        pattern: #"(\s)([A-Za-z_][A-Za-z0-9_.-]*):([A-Za-z_][A-Za-z0-9_.-]*)(?=\s*=)"#
    )
    private static let namespaceLikeElementRegex = try! NSRegularExpression(
        pattern: #"<(/?)([A-Za-z_][A-Za-z0-9_.-]*):([A-Za-z_][A-Za-z0-9_.-]*)"#
    )
    private static let attributeNameRegex = try! NSRegularExpression(
        pattern: #"\s([A-Za-z_][A-Za-z0-9_.:-]*)(?=\s*=)"#
    )
    private static let bareAmpersandRegex = try! NSRegularExpression(
        pattern: #"&(?!amp;|lt;|gt;|quot;|apos;|#[0-9]+;|#x[0-9A-Fa-f]+;)"#
    )

    private static func repairXMLForParsing(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let repairedAmpersands = bareAmpersandRegex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "&amp;"
        )
        let ampersandRange = NSRange(repairedAmpersands.startIndex..<repairedAmpersands.endIndex, in: repairedAmpersands)
        let repairedElements = namespaceLikeElementRegex.stringByReplacingMatches(
            in: repairedAmpersands,
            range: ampersandRange,
            withTemplate: "<$1$2_$3"
        )
        let repairedRange = NSRange(repairedElements.startIndex..<repairedElements.endIndex, in: repairedElements)
        let repairedNamespaces = namespaceLikeAttributeRegex.stringByReplacingMatches(
            in: repairedElements,
            range: repairedRange,
            withTemplate: "$1$2_$3"
        )
        return repairDuplicateAttributes(in: repairedNamespaces)
    }

    private static func repairDuplicateAttributes(in text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var cursor = text.startIndex
        var changed = false

        while let tagStart = text[cursor...].firstIndex(of: "<") {
            result += text[cursor..<tagStart]
            guard let tagEnd = text[tagStart...].firstIndex(of: ">") else {
                result += text[tagStart...]
                return changed ? result : text
            }

            let afterTagEnd = text.index(after: tagEnd)
            let tag = String(text[tagStart..<afterTagEnd])
            let repaired = repairDuplicateAttributes(inTag: tag)
            changed = changed || repaired != tag
            result += repaired
            cursor = afterTagEnd
        }

        result += text[cursor...]
        return changed ? result : text
    }

    private static func repairDuplicateAttributes(inTag tag: String) -> String {
        guard tag.hasPrefix("<"),
              !tag.hasPrefix("</"),
              !tag.hasPrefix("<?"),
              !tag.hasPrefix("<!") else {
            return tag
        }

        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        let matches = attributeNameRegex.matches(in: tag, range: range).compactMap { match -> (Range<String.Index>, String)? in
            guard match.numberOfRanges == 2,
                  let range = Range(match.range(at: 1), in: tag) else {
                return nil
            }
            return (range, String(tag[range]))
        }
        guard matches.count > 1 else {
            return tag
        }

        var seen: [String: Int] = [:]
        var result = ""
        result.reserveCapacity(tag.count)
        var cursor = tag.startIndex
        var changed = false

        for (range, name) in matches {
            result += tag[cursor..<range.lowerBound]
            let count = seen[name, default: 0] + 1
            seen[name] = count
            if count == 1 {
                result += name
            } else {
                result += "\(name)__duplicate\(count)"
                changed = true
            }
            cursor = range.upperBound
        }

        result += tag[cursor...]
        return changed ? result : tag
    }

    private static func mergeWheelRegistry(from root: XMLElement, basename: String, into indexes: inout ReferenceIndexes) {
        guard let wheelRoot = firstElement(named: "TruckWheels", under: root) else {
            return
        }
        var registry = indexes.wheelsByRegistry[basename] ?? WheelRegistry()
        for tireContainer in wheelRoot.elements(forName: "TruckTires") {
            for tire in tireContainer.elements(forName: "TruckTire") {
                if let name = normalizedAttribute(tire, "Name") {
                    registry.tires.insert(name)
                }
            }
        }
        for rimContainer in wheelRoot.elements(forName: "TruckRims") {
            for rim in rimContainer.elements(forName: "TruckRim") {
                if let name = normalizedAttribute(rim, "Name") {
                    registry.rims.insert(name)
                }
            }
        }
        indexes.wheelsByRegistry[basename] = registry
    }

    private static func registryParentBasename(from root: XMLElement) -> String? {
        guard let parent = firstElement(named: "_parent", under: root),
              let file = normalizedAttribute(parent, "File") else {
            return nil
        }
        return fileBasename(file)
    }

    private static func resolveRegistryInheritance(in indexes: inout ReferenceIndexes) {
        for name in Array(indexes.wheelsByRegistry.keys) {
            var visiting: Set<String> = []
            indexes.wheelsByRegistry[name] = resolvedWheelRegistry(name, indexes: indexes, visiting: &visiting)
        }
        indexes.enginesByRegistry = resolvedNamedRegistries(
            indexes.enginesByRegistry,
            parents: indexes.engineParents
        )
        indexes.gearboxesByRegistry = resolvedNamedRegistries(
            indexes.gearboxesByRegistry,
            parents: indexes.gearboxParents
        )
        indexes.suspensionsByRegistry = resolvedNamedRegistries(
            indexes.suspensionsByRegistry,
            parents: indexes.suspensionParents
        )
        indexes.winchesByRegistry = resolvedNamedRegistries(
            indexes.winchesByRegistry,
            parents: indexes.winchParents
        )
    }

    private static func resolvedWheelRegistry(
        _ name: String,
        indexes: ReferenceIndexes,
        visiting: inout Set<String>
    ) -> WheelRegistry {
        guard visiting.insert(name).inserted else {
            return indexes.wheelsByRegistry[name] ?? WheelRegistry()
        }
        var resolved = WheelRegistry()
        if let parent = indexes.wheelParents[name] {
            resolved = resolvedWheelRegistry(parent, indexes: indexes, visiting: &visiting)
        }
        if let child = indexes.wheelsByRegistry[name] {
            resolved.tires.formUnion(child.tires)
            resolved.rims.formUnion(child.rims)
        }
        visiting.remove(name)
        return resolved
    }

    private static func resolvedNamedRegistries(
        _ registries: [String: Set<String>],
        parents: [String: String]
    ) -> [String: Set<String>] {
        var resolved = registries
        for name in Array(registries.keys) {
            var visiting: Set<String> = []
            resolved[name] = resolvedNamedRegistry(name, registries: registries, parents: parents, visiting: &visiting)
        }
        return resolved
    }

    private static func resolvedNamedRegistry(
        _ name: String,
        registries: [String: Set<String>],
        parents: [String: String],
        visiting: inout Set<String>
    ) -> Set<String> {
        guard visiting.insert(name).inserted else {
            return registries[name] ?? []
        }
        var resolved: Set<String> = []
        if let parent = parents[name] {
            resolved.formUnion(resolvedNamedRegistry(parent, registries: registries, parents: parents, visiting: &visiting))
        }
        resolved.formUnion(registries[name] ?? [])
        visiting.remove(name)
        return resolved
    }

    private static func mergeNamedRegistry(
        from root: XMLElement,
        registryRootName: String,
        childName: String,
        basename: String,
        into registry: inout [String: Set<String>]
    ) {
        guard let registryRoot = firstElement(named: registryRootName, under: root) else {
            return
        }
        var names = registry[basename] ?? []
        for child in registryRoot.elements(forName: childName) {
            if let name = normalizedAttribute(child, "Name") {
                names.insert(name)
            }
        }
        registry[basename] = names
    }

    private static func validateParentReferences(
        in parsed: ParsedSource,
        indexes: ReferenceIndexes,
        issues: inout [ModReferenceIssue]
    ) {
        for parent in elements(named: "_parent", under: parsed.root) {
            guard let file = normalizedAttribute(parent, "File") else {
                continue
            }
            let basename = fileBasename(file)
            guard !indexes.classBasenames.contains(basename) else {
                continue
            }
            issues.append(ModReferenceIssue(
                sourcePath: parsed.path,
                referencedCategory: "parent class",
                missingValue: file,
                explanation: "_parent File does not resolve to a merged truck/addon class basename"
            ))
        }
    }

    private static func validateDefaultAddonReferences(
        in parsed: ParsedSource,
        indexes: ReferenceIndexes,
        issues: inout [ModReferenceIssue]
    ) {
        for sockets in elements(named: "AddonSockets", under: parsed.root) {
            guard let defaultAddon = normalizedAttribute(sockets, "DefaultAddon") else {
                continue
            }
            let basename = fileBasename(defaultAddon)
            guard !indexes.classBasenames.contains(basename) else {
                continue
            }
            issues.append(ModReferenceIssue(
                sourcePath: parsed.path,
                referencedCategory: "default addon",
                missingValue: defaultAddon,
                explanation: "AddonSockets DefaultAddon does not resolve to a merged truck/addon class basename"
            ))
        }
    }

    private static func validateWheelReferences(
        in parsed: ParsedSource,
        indexes: ReferenceIndexes,
        issues: inout [ModReferenceIssue]
    ) {
        for wheels in elements(named: "Wheels", under: parsed.root) {
            validateWheelSet(
                sourcePath: parsed.path,
                wheelType: normalizedAttribute(wheels, "DefaultWheelType"),
                tire: normalizedAttribute(wheels, "DefaultTire"),
                rim: normalizedAttribute(wheels, "DefaultRim"),
                indexes: indexes,
                issues: &issues
            )
        }

        for wheels in elements(named: "ExtraWheels", under: parsed.root) {
            validateWheelSet(
                sourcePath: parsed.path,
                wheelType: normalizedAttribute(wheels, "WheelType"),
                tire: normalizedAttribute(wheels, "Tire"),
                rim: normalizedAttribute(wheels, "Rim"),
                indexes: indexes,
                issues: &issues
            )
        }
    }

    private static func validateWheelSet(
        sourcePath: String,
        wheelType: String?,
        tire: String?,
        rim: String?,
        indexes: ReferenceIndexes,
        issues: inout [ModReferenceIssue]
    ) {
        guard let wheelType else {
            return
        }
        guard let registry = indexes.wheelsByRegistry[wheelType] else {
            issues.append(ModReferenceIssue(
                sourcePath: sourcePath,
                referencedCategory: "wheel class",
                missingValue: wheelType,
                explanation: "wheel registry class is not present in merged sources"
            ))
            return
        }
        if let tire, !registry.tires.contains(tire) {
            issues.append(ModReferenceIssue(
                sourcePath: sourcePath,
                referencedCategory: "tire",
                missingValue: tire,
                explanation: "\(wheelType) does not define tire \(tire)"
            ))
        }
        if let rim, !registry.rims.contains(rim) {
            issues.append(ModReferenceIssue(
                sourcePath: sourcePath,
                referencedCategory: "rim",
                missingValue: rim,
                explanation: "\(wheelType) does not define rim \(rim)"
            ))
        }
    }

    private static func validateUpgradeSocket(
        in parsed: ParsedSource,
        socketName: String,
        category: String,
        registries: [String: Set<String>],
        issues: inout [ModReferenceIssue]
    ) {
        for socket in elements(named: socketName, under: parsed.root) {
            guard let defaultValue = normalizedAttribute(socket, "Default") else {
                continue
            }
            let registryNames = splitRegistryList(normalizedAttribute(socket, "Type"))
            let availableVariants = registryNames.reduce(into: Set<String>()) { partial, registryName in
                partial.formUnion(registries[registryName] ?? [])
            }

            if availableVariants.isEmpty, !registryNames.isEmpty {
                issues.append(ModReferenceIssue(
                    sourcePath: parsed.path,
                    referencedCategory: "\(category) registry",
                    missingValue: registryNames.joined(separator: ", "),
                    explanation: "\(socketName) Type does not resolve to a merged registry class"
                ))
                continue
            }

            guard availableVariants.contains(defaultValue) else {
                issues.append(ModReferenceIssue(
                    sourcePath: parsed.path,
                    referencedCategory: category,
                    missingValue: defaultValue,
                    explanation: "\(socketName) Default is not defined by \(registryNames.joined(separator: ", "))"
                ))
                continue
            }
        }
    }

    private static func elements(named name: String, under root: XMLElement) -> [XMLElement] {
        var found: [XMLElement] = []
        collectElements(named: name, under: root, into: &found)
        return found
    }

    private static func firstElement(named name: String, under root: XMLElement) -> XMLElement? {
        if root.name == name {
            return root
        }
        for child in root.children ?? [] {
            guard let element = child as? XMLElement else {
                continue
            }
            if let found = firstElement(named: name, under: element) {
                return found
            }
        }
        return nil
    }

    private static func collectElements(named name: String, under root: XMLElement, into found: inout [XMLElement]) {
        if root.name == name {
            found.append(root)
        }
        for child in root.children ?? [] {
            guard let element = child as? XMLElement else {
                continue
            }
            collectElements(named: name, under: element, into: &found)
        }
    }

    private static func normalizedAttribute(_ element: XMLElement, _ name: String) -> String? {
        let value = element.attribute(forName: name)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func splitRegistryList(_ value: String?) -> [String] {
        guard let value else {
            return []
        }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isReferenceValidationXMLPath(_ path: String) -> Bool {
        isClassXMLPath(path)
            && (isTruckClassPath(path)
                || isWheelRegistryPath(path)
                || isEngineRegistryPath(path)
                || isGearboxRegistryPath(path)
                || isSuspensionRegistryPath(path)
                || isWinchRegistryPath(path))
    }

    private static func isClassXMLPath(_ path: String) -> Bool {
        let normalized = normalizedPath(path)
        return normalized.hasSuffix(".xml") && normalized.contains("\\classes\\")
    }

    private static func isTruckClassPath(_ path: String) -> Bool {
        normalizedPath(path).contains("\\classes\\trucks\\")
    }

    private static func isWheelRegistryPath(_ path: String) -> Bool {
        isRegistryPath(path, folder: "wheels")
    }

    private static func isEngineRegistryPath(_ path: String) -> Bool {
        isRegistryPath(path, folder: "engines")
    }

    private static func isGearboxRegistryPath(_ path: String) -> Bool {
        isRegistryPath(path, folder: "gearboxes")
    }

    private static func isSuspensionRegistryPath(_ path: String) -> Bool {
        isRegistryPath(path, folder: "suspensions")
    }

    private static func isWinchRegistryPath(_ path: String) -> Bool {
        isRegistryPath(path, folder: "winches") && fileBasename(path).hasPrefix("winches_")
    }

    private static func isRegistryPath(_ path: String, folder: String) -> Bool {
        normalizedPath(path).contains("\\classes\\\(folder)\\")
    }

    private static func normalizedPath(_ path: String) -> String {
        path.lowercased().replacingOccurrences(of: "/", with: "\\")
    }

    private static func fileBasename(_ internalName: String) -> String {
        let separators = CharacterSet(charactersIn: "\\/")
        let file = internalName.components(separatedBy: separators).last ?? internalName
        return file.hasSuffix(".xml") ? String(file.dropLast(4)) : file
    }
}
