import Foundation

@main
struct QuickRulesTests {
    static func main() throws {
        let uuid = "e028d625-71bb-4d97-bc0a-0c9c041a5975"
        let row = uuid + " — 15000 VES ($14.80)"
        let source = "Email: private@example.com\nПоследние депозиты:\n100 USD\n\nПоследние заявки:\n" + row
        let caption = try require(AnchorQuickRules.latestRequests(source))
        precondition(!caption.contains("Email"))
        precondition(!caption.contains("Последние заявки"))
        precondition(AnchorQuickRules.requestIds(caption) == [uuid])
        let cl = "CL9911864006_1792171727011"
        let alternative = "Последние заявки:\n\u{200e}" + cl + " – 20 USD\u{2028}($20.00)"
        precondition(AnchorQuickRules.latestRequests(alternative) != nil)
        precondition(AnchorQuickRules.requestIds(alternative) == [cl.lowercased()])
        precondition(AnchorQuickRules.latestRequests("Последние заявки:\nwrong row\n" + row) == nil)
        precondition(AnchorQuickRules.latestRequests("Последние заявки:\n") == nil)
        precondition(AnchorQuickRules.latestRequests(row) == nil)
        precondition(AnchorQuickRules.requestIds(row + "\n" + row).count == 1)
        precondition(AnchorQuickRules.latestRequests(source + "\nНовый раздел:\nEmail: other@example.com") == caption)
        precondition(AnchorQuickRules.latestRequests(String(repeating: "x", count: 262145)) == nil)
        let target = AnchorQuickTarget(id: "button", label: "Группа", destination: "Группа", peer: 123, thread: 456, requestsOnly: true)
        let decoded = try JSONDecoder().decode(AnchorQuickTarget.self, from: JSONEncoder().encode(target))
        precondition(decoded == target)
        print("Quick forwarding parser and configuration tests passed.")
    }

    static func require(_ value: String?) throws -> String {
        guard let value else { throw NSError(domain: "MissingCaption", code: 1) }
        return value
    }
}
