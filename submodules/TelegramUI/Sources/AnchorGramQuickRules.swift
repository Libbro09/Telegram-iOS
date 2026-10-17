import Foundation

struct AnchorQuickTarget: Codable, Equatable {
    var id: String
    var label: String
    var destination: String
    var peer: Int64
    var thread: Int64?
    var requestsOnly: Bool
}

enum AnchorQuickRules {
    private static let identifier = "(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[a-z][a-z0-9]{2,63}_[0-9]{4,32})"
    private static let ids = try! NSRegularExpression(pattern: "(?<![a-z0-9])" + identifier + "(?![a-z0-9])", options: .caseInsensitive)
    private static let header = try! NSRegularExpression(pattern: "\\A\\s*Последние\\s+заявки\\s*:\\s*\\z", options: .caseInsensitive)
    private static let amount = "[0-9][0-9., ]{0,24}"
    private static let row = try! NSRegularExpression(pattern: "\\A\\s*" + identifier + "\\s*-\\s*" + amount + "\\s+[a-z]{2,12}(?:\\s*\\(\\s*\\$?" + amount + "\\s*\\))?\\s*\\z", options: .caseInsensitive)
    private static let dollars = try! NSRegularExpression(pattern: "\\A\\s*\\(\\s*\\$?" + amount + "\\s*\\)\\s*\\z")

    static func normalized(_ text: String) -> String {
        var text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for value in ["\u{2028}", "\u{2029}"] { text = text.replacingOccurrences(of: value, with: "\n") }
        for value in ["\u{00a0}", "\u{202f}"] { text = text.replacingOccurrences(of: value, with: " ") }
        for value in ["\u{200e}", "\u{200f}", "\u{202a}", "\u{202b}", "\u{202c}", "\u{202d}", "\u{202e}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{feff}"] { text = text.replacingOccurrences(of: value, with: "") }
        for value in ["\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}"] { text = text.replacingOccurrences(of: value, with: "-") }
        return text
    }

    static func requestIds(_ text: String) -> [String] {
        guard text.utf8.count <= 262144 else { return [] }
        let text = normalized(text)
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var result: [String] = []
        for match in ids.matches(in: text, range: range) {
            guard let range = Range(match.range, in: text) else { continue }
            let id = String(text[range]).lowercased()
            if seen.insert(id).inserted { result.append(id) }
            if result.count == 21 { break }
        }
        return result
    }

    static func latestRequests(_ text: String) -> String? {
        guard text.utf8.count <= 262144 else { return nil }
        let lines = normalized(text).components(separatedBy: "\n")
        guard lines.count <= 2000, let start = lines.firstIndex(where: { matches(header, $0) }) else { return nil }
        var result: [String] = []
        var acceptsDollars = false
        for raw in lines.dropFirst(start + 1) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasSuffix(":") { break }
            if matches(row, line) {
                result.append(line)
                acceptsDollars = !line.contains("(")
            } else if acceptsDollars && matches(dollars, line) {
                result.append(line)
                acceptsDollars = false
            } else {
                return nil
            }
            if result.count > 40 { return nil }
        }
        let caption = result.joined(separator: "\n")
        guard !caption.isEmpty, caption.utf16.count <= 1024 else { return nil }
        return caption
    }

    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
