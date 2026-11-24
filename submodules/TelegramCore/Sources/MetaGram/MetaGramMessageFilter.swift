import Foundation
import Postbox
import SwiftSignalKit

/// MetaGram "Filters": hides messages that match a filter or come from a shadow-banned user.
public enum MetaGramMessageFilter {
    private static let cache = Atomic<(key: [String], regexes: [NSRegularExpression])>(value: (key: [], regexes: []))

    private static func regexes() -> [NSRegularExpression] {
        let patterns = MetaGramSettings.list(.messageFilters)
        return cache.modify { current in
            if current.key == patterns {
                return current
            }
            let compiled = patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
            return (key: patterns, regexes: compiled)
        }.regexes
    }

    /// Whether the chat should not show this message. Outgoing messages are never hidden.
    public static func shouldHide(_ message: Message) -> Bool {
        if !message.flags.contains(.Incoming) {
            return false
        }
        if let authorId = message.author?.id {
            let banned = MetaGramSettings.list(.shadowBanned)
            if !banned.isEmpty && banned.contains("\(authorId.toInt64())") {
                return true
            }
        }
        if MetaGramSettings.get(.enableFilters) && !message.text.isEmpty {
            let text = message.text
            let range = NSRange(text.startIndex..., in: text)
            for regex in regexes() {
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    return true
                }
            }
        }
        return false
    }
}
