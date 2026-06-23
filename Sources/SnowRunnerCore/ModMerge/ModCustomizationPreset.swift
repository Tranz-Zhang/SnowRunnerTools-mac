import Foundation

public enum ModCustomizationPreset {
    public static let internalName = "[media]\\classes\\customization_presets\\customization_preset.xml"

    public static func merge(baseData: Data, modData: Data, path: String) throws -> Data {
        let base = try parse(baseData, path: path)
        let mod = try parse(modData, path: path)
        let mergedRoot = XMLElement(name: "TruckSet")
        var mergedByName = base.trucksByName
        var order = base.order

        for truckName in mod.order {
            if mergedByName[truckName] == nil {
                order.append(truckName)
            }
            mergedByName[truckName] = mod.trucksByName[truckName]
        }

        for truckName in order {
            guard let truck = mergedByName[truckName]?.copy() as? XMLElement else {
                continue
            }
            mergedRoot.addChild(truck)
        }

        let document = XMLDocument(rootElement: mergedRoot)
        return document.xmlData(options: [.nodePrettyPrint])
    }

    private struct ParsedTruckSet {
        let order: [String]
        let trucksByName: [String: XMLElement]
    }

    private static func parse(_ data: Data, path: String) throws -> ParsedTruckSet {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [])
        } catch {
            guard let repaired = repairDuplicateTintColorAttributes(in: data) else {
                throw ModMergeError.invalidCustomizationPreset(path: path, reason: "could not parse XML: \(error)")
            }
            do {
                document = try XMLDocument(data: repaired, options: [])
            } catch {
                throw ModMergeError.invalidCustomizationPreset(path: path, reason: "could not parse XML: \(error)")
            }
        }

        guard let root = document.rootElement(), root.name == "TruckSet" else {
            throw ModMergeError.invalidCustomizationPreset(path: path, reason: "root element must be TruckSet")
        }

        var order: [String] = []
        var trucksByName: [String: XMLElement] = [:]
        for truck in root.elements(forName: "Truck") {
            let name = truck.attribute(forName: "Name")?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else {
                throw ModMergeError.invalidCustomizationPreset(path: path, reason: "Truck element is missing Name")
            }
            if trucksByName[name] == nil {
                order.append(name)
            }
            trucksByName[name] = truck
        }

        return ParsedTruckSet(order: order, trucksByName: trucksByName)
    }

    private struct TintColorAttributeMatch {
        var range: Range<String.Index>
        var name: String
    }

    private static let tintColorAttributeNames = ["TintColor1", "TintColor2", "TintColor3"]
    private static let tintColorAttributeRegex = try! NSRegularExpression(pattern: #"TintColor[123](?=\s*=)"#)

    private static func repairDuplicateTintColorAttributes(in data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        var result = ""
        result.reserveCapacity(text.count)
        var cursor = text.startIndex
        var changed = false

        while let tagStart = text[cursor...].range(of: "<CustomizationPreset") {
            result += text[cursor..<tagStart.lowerBound]

            guard let tagEnd = text[tagStart.lowerBound...].firstIndex(of: ">") else {
                result += text[tagStart.lowerBound...]
                cursor = text.endIndex
                break
            }

            let afterTagEnd = text.index(after: tagEnd)
            let tag = String(text[tagStart.lowerBound..<afterTagEnd])
            let repairedTag = repairDuplicateTintColorAttributes(inTag: tag)
            changed = changed || repairedTag != tag
            result += repairedTag
            cursor = afterTagEnd
        }

        result += text[cursor...]
        return changed ? Data(result.utf8) : nil
    }

    private static func repairDuplicateTintColorAttributes(inTag tag: String) -> String {
        let nsRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        let matches = tintColorAttributeRegex.matches(in: tag, range: nsRange).compactMap { match -> TintColorAttributeMatch? in
            guard let range = Range(match.range, in: tag) else {
                return nil
            }
            return TintColorAttributeMatch(range: range, name: String(tag[range]))
        }
        guard matches.count > 1 else {
            return tag
        }

        var assigned: Set<String> = []
        var result = ""
        result.reserveCapacity(tag.count)
        var cursor = tag.startIndex
        var changed = false

        for (index, match) in matches.enumerated() {
            result += tag[cursor..<match.range.lowerBound]

            let replacement: String
            if assigned.contains(match.name) {
                let remainingOriginalNames = Set(matches.dropFirst(index + 1).map(\.name))
                replacement = promotedTintColorName(
                    assigned: assigned,
                    remainingOriginalNames: remainingOriginalNames
                ) ?? match.name
                changed = changed || replacement != match.name
            } else {
                replacement = match.name
            }

            assigned.insert(replacement)
            result += replacement
            cursor = match.range.upperBound
        }

        result += tag[cursor...]
        return changed ? result : tag
    }

    private static func promotedTintColorName(
        assigned: Set<String>,
        remainingOriginalNames: Set<String>
    ) -> String? {
        for name in tintColorAttributeNames where !assigned.contains(name) && !remainingOriginalNames.contains(name) {
            return name
        }
        return tintColorAttributeNames.first { !assigned.contains($0) }
    }
}
