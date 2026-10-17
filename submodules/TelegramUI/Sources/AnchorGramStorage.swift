import Foundation

func anchorgramAppGroupName(baseAppBundleId: String) -> String {
    return (Bundle.main.object(forInfoDictionaryKey: "AnchorGramAppGroup") as? String) ?? "group.\(baseAppBundleId)"
}

func anchorgramContainerURL(appGroupName: String, baseAppBundleId: String) -> URL? {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName) else {
        return nil
    }
    if appGroupName == "group.\(baseAppBundleId)" {
        return container
    }
    let isolated = container.appendingPathComponent("AnchorGram", isDirectory: true).appendingPathComponent(baseAppBundleId, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: true)
        return isolated
    } catch {
        return nil
    }
}
