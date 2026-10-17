import Foundation

@main
struct AccessGroupTests {
    static func main() {
        let own = "ABCD123456.app.example.anchorgram"
        precondition(PasscodeAccessGroupPolicy.acceptsOverride(own, resolvedPrivateGroup: own, isMainApp: true))
        precondition(!PasscodeAccessGroupPolicy.acceptsOverride(own, resolvedPrivateGroup: nil, isMainApp: true))
        precondition(!PasscodeAccessGroupPolicy.acceptsOverride(own, resolvedPrivateGroup: "ABCD123456.app.other", isMainApp: true))
        precondition(!PasscodeAccessGroupPolicy.acceptsOverride(own, resolvedPrivateGroup: own, isMainApp: false))
        for invalid in ["group.example.1", "ABCD.app.example", "ABCD123456.app..example", "ABCD123456.app.example.", "ABCD123456.app.example\n"] {
            precondition(!PasscodeAccessGroupPolicy.acceptsOverride(invalid, resolvedPrivateGroup: invalid, isMainApp: true))
        }
        print("Passcode access group checks passed.")
    }
}
