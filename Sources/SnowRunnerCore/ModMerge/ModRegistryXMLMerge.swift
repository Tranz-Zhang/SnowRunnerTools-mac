import Foundation

public enum ModRegistryXMLMerge {
    public static func isSupportedRegistryPath(_ internalName: String) -> Bool {
        rule(for: internalName) != nil
    }

    public static func merge(baseData: Data, modData: Data, path: String) throws -> Data {
        guard let rule = rule(for: path) else {
            throw ModMergeError.invalidRegistryXML(path: path, reason: "unsupported registry path")
        }

        let baseDocument = try parse(baseData, path: path, expectedRoot: rule.rootName)
        let modDocument = try parse(modData, path: path, expectedRoot: rule.rootName)
        let baseRoot = baseDocument.registryRoot
        let modRoot = modDocument.registryRoot

        switch rule {
        case let .nested(expectedRoot, collections):
            precondition(baseRoot.name == expectedRoot)
            for collection in collections {
                try mergeNestedCollection(
                    baseRoot: baseRoot,
                    modRoot: modRoot,
                    collection: collection,
                    path: path
                )
            }
        case let .direct(expectedRoot, childName):
            precondition(baseRoot.name == expectedRoot)
            try mergeDirectChildren(baseRoot: baseRoot, modRoot: modRoot, childName: childName, path: path)
        }

        return render(baseDocument)
    }

    private enum Rule {
        case nested(root: String, collections: [CollectionRule])
        case direct(root: String, childName: String)

        var rootName: String {
            switch self {
            case let .nested(root, _), let .direct(root, _):
                return root
            }
        }
    }

    private struct CollectionRule {
        let containerName: String
        let childName: String
    }

    private static func rule(for internalName: String) -> Rule? {
        let normalized = internalName.lowercased()
        guard normalized.hasSuffix(".xml"), normalized.contains("\\classes\\") else {
            return nil
        }

        if normalized.contains("\\classes\\wheels\\") {
            return .nested(
                root: "TruckWheels",
                collections: [
                    CollectionRule(containerName: "TruckTires", childName: "TruckTire"),
                    CollectionRule(containerName: "TruckRims", childName: "TruckRim")
                ]
            )
        }
        if normalized.contains("\\classes\\engines\\") {
            return .direct(root: "EngineVariants", childName: "Engine")
        }
        if normalized.contains("\\classes\\gearboxes\\") {
            return .direct(root: "GearboxVariants", childName: "Gearbox")
        }
        if normalized.contains("\\classes\\suspensions\\") {
            return .direct(root: "SuspensionSetVariants", childName: "SuspensionSet")
        }
        if normalized.contains("\\classes\\winches\\"), fileBasename(normalized).hasPrefix("winches_") {
            return .direct(root: "WinchVariants", childName: "Winch")
        }
        return nil
    }

    private struct ParsedDocument {
        let document: XMLDocument
        let registryRoot: XMLElement
        let wasWrapped: Bool
    }

    private static func parse(_ data: Data, path: String, expectedRoot: String) throws -> ParsedDocument {
        do {
            let document = try XMLDocument(data: data, options: [])
            if let root = document.rootElement(), root.name == expectedRoot {
                return ParsedDocument(document: document, registryRoot: root, wasWrapped: false)
            }
        } catch {
            return try parseWrapped(data, path: path, expectedRoot: expectedRoot, originalError: error)
        }

        return try parseWrapped(data, path: path, expectedRoot: expectedRoot, originalError: nil)
    }

    private static func parseWrapped(
        _ data: Data,
        path: String,
        expectedRoot: String,
        originalError: Error?
    ) throws -> ParsedDocument {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ModMergeError.invalidRegistryXML(path: path, reason: "XML is not UTF-8")
        }
        let wrapped = "<_ModRegistryXMLMergeRoot>\n\(text)\n</_ModRegistryXMLMergeRoot>"
        do {
            let document = try XMLDocument(data: Data(wrapped.utf8), options: [])
            guard let syntheticRoot = document.rootElement(),
                  let registryRoot = syntheticRoot.elements(forName: expectedRoot).first else {
                throw ModMergeError.invalidRegistryXML(path: path, reason: "root element must be \(expectedRoot)")
            }
            return ParsedDocument(document: document, registryRoot: registryRoot, wasWrapped: true)
        } catch let error as ModMergeError {
            throw error
        } catch {
            let reason = originalError.map { "could not parse XML: \($0)" } ?? "could not parse XML: \(error)"
            throw ModMergeError.invalidRegistryXML(path: path, reason: reason)
        }
    }

    private static func mergeNestedCollection(
        baseRoot: XMLElement,
        modRoot: XMLElement,
        collection: CollectionRule,
        path: String
    ) throws {
        guard let modContainer = modRoot.elements(forName: collection.containerName).first else {
            return
        }

        let baseContainer: XMLElement
        if let existing = baseRoot.elements(forName: collection.containerName).first {
            baseContainer = existing
        } else {
            guard let copied = modContainer.copy() as? XMLElement else {
                return
            }
            baseRoot.addChild(copied)
            return
        }

        try mergeKeyedChildren(
            baseContainer: baseContainer,
            modContainer: modContainer,
            childName: collection.childName,
            path: path
        )
    }

    private static func mergeDirectChildren(
        baseRoot: XMLElement,
        modRoot: XMLElement,
        childName: String,
        path: String
    ) throws {
        try mergeKeyedChildren(
            baseContainer: baseRoot,
            modContainer: modRoot,
            childName: childName,
            path: path
        )
    }

    private static func mergeKeyedChildren(
        baseContainer: XMLElement,
        modContainer: XMLElement,
        childName: String,
        path: String
    ) throws {
        var childrenByName: [String: XMLElement] = [:]
        var order: [String] = []

        for child in baseContainer.elements(forName: childName) {
            let name = try requiredName(from: child, childName: childName, path: path)
            if childrenByName[name] == nil {
                order.append(name)
            }
            childrenByName[name] = child
        }

        for child in modContainer.elements(forName: childName) {
            let name = try requiredName(from: child, childName: childName, path: path)
            if childrenByName[name] == nil {
                order.append(name)
            }
            childrenByName[name] = child
        }

        replaceChildren(of: baseContainer, with: order.compactMap { childrenByName[$0] })
    }

    private static func requiredName(from element: XMLElement, childName: String, path: String) throws -> String {
        let name = element.attribute(forName: "Name")?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            throw ModMergeError.invalidRegistryXML(path: path, reason: "\(childName) element is missing Name")
        }
        return name
    }

    private static func replaceChildren(of element: XMLElement, with children: [XMLElement]) {
        while element.childCount > 0 {
            element.removeChild(at: 0)
        }
        for child in children {
            guard let copied = child.copy() as? XMLElement else {
                continue
            }
            element.addChild(copied)
        }
    }

    private static func render(_ parsed: ParsedDocument) -> Data {
        guard parsed.wasWrapped else {
            return parsed.document.xmlData(options: [.nodePrettyPrint])
        }
        guard let syntheticRoot = parsed.document.rootElement() else {
            return parsed.document.xmlData(options: [.nodePrettyPrint])
        }
        let text = (syntheticRoot.children ?? [])
            .map { $0.xmlString(options: [.nodePrettyPrint]) }
            .joined(separator: "\n")
        return Data(text.utf8)
    }

    private static func fileBasename(_ internalName: String) -> String {
        let separators = CharacterSet(charactersIn: "\\/")
        let file = internalName.components(separatedBy: separators).last ?? internalName
        return file.hasSuffix(".xml") ? String(file.dropLast(4)) : file
    }
}
