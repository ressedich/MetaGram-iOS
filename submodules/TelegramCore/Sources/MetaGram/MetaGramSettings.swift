import Foundation

/// MetaGram client settings (ghost mode and friends).
///
/// Stored in the app's UserDefaults, read on every request, so a change applies at once.
public enum MetaGramSettings {
    public enum Key: String, CaseIterable, Sendable {
        /// Do not send read receipts (messages stay unread for the sender).
        case dontReadMessages = "metagram.ghost.dontReadMessages"
        /// Do not mark stories as viewed.
        case dontReadStories = "metagram.ghost.dontReadStories"
        /// Never report "online"; the account always looks offline.
        case dontSendOnline = "metagram.ghost.dontSendOnline"
        /// Do not send "typing…", "recording…", upload progress.
        case dontSendTyping = "metagram.ghost.dontSendTyping"
        /// Do not load sponsored messages in channels.
        case disableAds = "metagram.disableAds"
        /// Keep messages deleted by others, marked as deleted.
        case saveDeletedMessages = "metagram.spy.saveDeletedMessages"
        /// Keep earlier versions of edited messages.
        case saveEditsHistory = "metagram.spy.saveEditsHistory"
    }

    /// The options the "Ghost Mode" switch turns on and off together.
    public static let ghostKeys: [Key] = [.dontReadMessages, .dontReadStories, .dontSendOnline, .dontSendTyping]

    public static func get(_ key: Key) -> Bool {
        return UserDefaults.standard.bool(forKey: key.rawValue)
    }

    public static func set(_ key: Key, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    /// Ghost mode counts as on when every ghost option is on.
    public static var isGhostModeEnabled: Bool {
        return ghostKeys.allSatisfy { get($0) }
    }

    public static func setGhostMode(_ enabled: Bool) {
        for key in ghostKeys {
            set(key, enabled)
        }
    }

    /// Whether a request to the server must not be sent, by its TL function name.
    /// A blocked request completes with no value, as a request whose answer was dropped:
    /// operations queued for it are then cleared instead of being retried.
    static func blocksRequest(named name: String) -> Bool {
        switch name {
        case "messages.readHistory", "channels.readHistory", "messages.readDiscussion",
             "messages.readSavedHistory", "messages.readMessageContents",
             "channels.readMessageContents", "messages.readEncryptedHistory":
            return get(.dontReadMessages)
        case "stories.readStories", "stories.incrementStoryViews":
            return get(.dontReadStories)
        case "messages.setTyping", "messages.setEncryptedTyping":
            return get(.dontSendTyping)
        case "messages.getSponsoredMessages":
            return get(.disableAds)
        default:
            return false
        }
    }
}
