import Foundation

enum PasscodeAccessGroupPolicy {
    static func acceptsOverride(_ group: String, resolvedPrivateGroup: String?, isMainApp: Bool) -> Bool {
        guard isMainApp, group == resolvedPrivateGroup else {
            return false
        }
        return group.range(of: "\\A[A-Z0-9]{10}\\.[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+\\z", options: .regularExpression) != nil
    }
}
