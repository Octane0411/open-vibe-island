import Foundation

/// Turns a reply that is a bare JSON object or array — common when an agent
/// runs with structured output — into a Markdown list of "**key**: value"
/// items, so a completion card (rendered as Markdown) reads like text instead
/// of one long run of braces and quotes. Anything that isn't JSON comes back
/// unchanged.
public enum StructuredReplyFormatter {
    public static func readable(_ text: String) -> String {
        let body = unfenced(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let first = body.first, first == "{" || first == "[",
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return text
        }

        let blocks: [String]
        switch object {
        case let dictionary as [String: Any]:
            blocks = lines(for: dictionary, source: body)
        case let array as [Any]:
            blocks = array.map { element in
                if let dictionary = element as? [String: Any] {
                    return self.lines(for: dictionary, source: body).joined(separator: "\n")
                }
                return "- " + inline(element)
            }
        default:
            return text
        }

        let result = blocks.joined(separator: containsObjects(object) ? "\n\n" : "\n")
        return result.isEmpty ? text : result
    }

    /// Strips a surrounding ``` / ```json fence.
    private static func unfenced(_ text: String) -> String {
        guard text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6 else { return text }
        var inner = text.dropFirst(3).dropLast(3)
        if let newline = inner.firstIndex(of: "\n") {
            inner = inner[inner.index(after: newline)...]
        }
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsObjects(_ object: Any) -> Bool {
        (object as? [Any])?.contains { $0 is [String: Any] } == true
    }

    /// Keys in the order they appear in the source; JSONSerialization drops it.
    private static func lines(for dictionary: [String: Any], source: String) -> [String] {
        dictionary.keys
            .sorted { lhs, rhs in
                let l = source.range(of: "\"\(lhs)\"")?.lowerBound ?? source.endIndex
                let r = source.range(of: "\"\(rhs)\"")?.lowerBound ?? source.endIndex
                return l == r ? lhs < rhs : l < r
            }
            .map { key in "- **\(key.replacingOccurrences(of: "_", with: " "))**: \(inline(dictionary[key] as Any))" }
    }

    private static func inline(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        case let array as [Any]:
            return array.map(inline).joined(separator: ", ")
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().map { "\($0) \(inline(dictionary[$0] as Any))" }.joined(separator: "; ")
        case is NSNull:
            return "—"
        default:
            return String(describing: value)
        }
    }
}
