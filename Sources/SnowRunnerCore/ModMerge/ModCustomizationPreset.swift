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
            throw ModMergeError.invalidCustomizationPreset(path: path, reason: "could not parse XML: \(error)")
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
}
