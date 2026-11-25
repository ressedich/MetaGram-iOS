import SwiftSignalKit
import Foundation

/// MetaGram client settings (ghost mode and friends).
///
/// Stored in the app's UserDefaults, read where they apply, so a change applies at once.
public enum MetaGramSettings {
    public enum Key: String, CaseIterable, Sendable {
        // Ghost mode
        /// Do not send read receipts (messages stay unread for the sender).
        case dontReadMessages = "metagram.ghost.dontReadMessages"
        /// Do not mark stories as viewed.
        case dontReadStories = "metagram.ghost.dontReadStories"
        /// Never report "online"; the account always looks offline.
        case dontSendOnline = "metagram.ghost.dontSendOnline"
        /// Do not send "typing…", "recording…", upload progress.
        case dontSendTyping = "metagram.ghost.dontSendTyping"
        /// Report "offline" right after every "online" report.
        case goOfflineAutomatically = "metagram.ghost.goOfflineAutomatically"
        /// While messages are not read, read a chat when you send a message or a reaction to it.
        case readOnInteract = "metagram.ghost.readOnInteract"
        /// Send messages without sound by default.
        case sendWithoutSound = "metagram.ghost.sendWithoutSound"
        /// Ask before opening a story while stories are marked as viewed.
        case storyGhostAlert = "metagram.ghost.storyAlert"

        // Spy
        /// Keep messages deleted by others, marked as deleted.
        case saveDeletedMessages = "metagram.spy.saveDeletedMessages"
        /// Keep earlier versions of edited messages.
        case saveEditsHistory = "metagram.spy.saveEditsHistory"
        /// Also keep deleted messages in chats with bots.
        case saveInBotDialogs = "metagram.spy.saveInBotDialogs"

        // Other
        /// Do not load sponsored messages in channels.
        case disableAds = "metagram.disableAds"
        /// Unlock Premium-only features shown by the client (local only; the server still decides).
        case localPremium = "metagram.localPremium"

        // Chats
        /// Show the ID of users, groups and channels in their profile.
        case showPeerId = "metagram.chats.showPeerId"
        /// Show seconds in message times.
        case showMessageSeconds = "metagram.chats.showMessageSeconds"
        /// Hide reactions under messages.
        case hideReactions = "metagram.chats.hideReactions"
        /// Draw messages deleted by others semi-transparent.
        case translucentDeleted = "metagram.chats.translucentDeleted"
        /// Mark deleted and edited messages with icons instead of words.
        case markWithIcons = "metagram.chats.markWithIcons"
        /// Do not show the greeting sticker in an empty chat.
        case disableGreetingSticker = "metagram.chats.disableGreetingSticker"
        /// Draw replies and link previews without the sender's color.
        case disableColorfulReplies = "metagram.chats.disableColorfulReplies"
        /// Ask before sending a sticker.
        case confirmStickers = "metagram.chats.confirmStickers"
        /// Ask before sending a GIF.
        case confirmGifs = "metagram.chats.confirmGifs"
        /// Ask before sending a voice or video message.
        case confirmVoice = "metagram.chats.confirmVoice"

        // General
        /// Hide stories everywhere.
        case disableStories = "metagram.general.disableStories"
        /// Do not show similar channels after joining a channel.
        case hideSimilarChannels = "metagram.general.hideSimilarChannels"
        /// Open links without the "Open this link?" confirmation.
        case disableLinkWarning = "metagram.general.disableLinkWarning"
        /// Strip "zalgo" combining marks from message texts.
        case filterZalgo = "metagram.general.filterZalgo"
        /// Present the session as an Android device (read by MtProtoKit's MTApiEnvironment; applies after a restart).
        case spoofAndroid = "metagram.general.spoofAndroid"
        /// Send messages about 12 seconds later, as scheduled messages, so they can still be cancelled.
        case delayedSend = "metagram.chats.delayedSend"
        /// Clearing the whole chat by the other side does not remove it here.
        case keepClearedHistory = "metagram.spy.keepClearedHistory"
        /// Ignore "Restrict saving content": forward, copy and save from protected chats. Protected messages are sent
        /// as new messages with their media downloaded and uploaded again, since the server refuses to forward them.
        case bypassCopyProtection = "metagram.spy.bypassCopyProtection"
        /// Self-destructing and view-once media stays viewable after its timer runs out.
        case keepSelfDestructingMedia = "metagram.spy.keepSelfDestructingMedia"
        /// Keep a per-chat log of deletions, edits and profile changes ("MetaGram Logs" in the profile).
        case eventLog = "metagram.spy.eventLog"
        /// Anyone's stories can be saved, protected ones too.
        case downloadStories = "metagram.spy.downloadStories"
        /// Upload and download files with more parallel parts.
        case speedBoost = "metagram.media.speedBoost"
        /// "Send as Video Message" for videos picked from the gallery.
        case sendVideoAsRound = "metagram.media.sendVideoAsRound"
        /// A Live Activity shows the MetaGram logo in the Dynamic Island while the app runs.
        case islandBadge = "metagram.appearance.islandBadge"

        // Appearance
        /// Hide names, phone numbers and avatars of chats in lists (for screen sharing).
        case streamerMode = "metagram.appearance.streamerMode"
        /// Hide emoji statuses next to names.
        case hidePremiumStatuses = "metagram.appearance.hidePremiumStatuses"
        /// Hide unread counters in the chat list and on the app icon.
        case hideNotificationCounters = "metagram.appearance.hideNotificationCounters"

        // Filters
        /// Hide messages that match the message filters.
        case enableFilters = "metagram.filters.enabled"
        /// Hide messages from users you blocked in groups.
        case hideFromBlocked = "metagram.filters.hideFromBlocked"
    }

    /// The options the "Ghost Mode" switch turns on and off together.
    public static let ghostKeys: [Key] = [.dontReadMessages, .dontReadStories, .dontSendOnline, .dontSendTyping]

    /// Options that are on in a fresh install.
    private static let defaultOn: Set<Key> = [.readOnInteract, .saveInBotDialogs, .translucentDeleted, .bypassCopyProtection, .keepSelfDestructingMedia, .eventLog, .downloadStories, .sendVideoAsRound, .islandBadge]

    public static func get(_ key: Key) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key.rawValue) == nil {
            return defaultOn.contains(key)
        }
        return defaults.bool(forKey: key.rawValue)
    }

    public static func set(_ key: Key, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    /// Whether the client ignores the server's copy protection ("Restrict saving content").
    public static var isCopyProtectionBypassed: Bool {
        return get(.bypassCopyProtection)
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

    // MARK: - Local Premium

    /// The users of this device's accounts (`PeerId.toInt64()`), registered as each account is created.
    private static let accountPeerIds = Atomic<Set<Int64>>(value: Set())

    static func registerAccountPeer(_ peerId: Int64) {
        let _ = accountPeerIds.modify { current in
            var current = current
            current.insert(peerId)
            return current
        }
    }

    /// Whether `peerId` is the user of one of this device's accounts.
    static func isAccountPeer(_ peerId: Int64) -> Bool {
        return accountPeerIds.with { $0.contains(peerId) }
    }

    /// Whether `peerId` is one of this device's accounts and "Local Telegram Premium" is on: the client then treats
    /// it as Premium. The server still sees a regular account.
    static func hasLocalPremium(peerId: Int64) -> Bool {
        if !get(.localPremium) {
            return false
        }
        return accountPeerIds.with { $0.contains(peerId) }
    }

    // MARK: - Lists

    public enum ListKey: String, Sendable {
        /// Message filters: a message whose text matches one of these (regular expression, case-insensitive) is hidden.
        case messageFilters = "metagram.filters.patterns"
        /// Shadow-banned users and chats (peer ids, `PeerId.toInt64()`): their messages are hidden.
        case shadowBanned = "metagram.filters.shadowBanned"
    }

    public static func list(_ key: ListKey) -> [String] {
        return UserDefaults.standard.stringArray(forKey: key.rawValue) ?? []
    }

    public static func setList(_ key: ListKey, _ value: [String]) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    // MARK: - Request blocking

    /// Until this time (seconds since 1970) read requests are let through, for "Read on Interact".
    private static let readBypassUntil = Atomic<Double>(value: 0)

    /// Lets read requests through for a short while (the read caused by sending a message or a reaction).
    public static func allowReadingBriefly() {
        let until = Date().timeIntervalSince1970 + 3.0
        let _ = readBypassUntil.swap(until)
    }

    private static var isReadBypassActive: Bool {
        return Date().timeIntervalSince1970 < readBypassUntil.with { $0 }
    }

    /// Whether a request to the server must not be sent, by its TL function name.
    /// A blocked request completes with no value, as a request whose answer was dropped:
    /// operations queued for it are then cleared instead of being retried.
    static func blocksRequest(named name: String) -> Bool {
        switch name {
        case "messages.readHistory", "channels.readHistory", "messages.readDiscussion",
             "messages.readSavedHistory", "messages.readMessageContents",
             "channels.readMessageContents", "messages.readEncryptedHistory":
            return get(.dontReadMessages) && !isReadBypassActive
        case "stories.readStories", "stories.incrementStoryViews":
            return get(.dontReadStories)
        case "messages.setTyping", "messages.setEncryptedTyping":
            return get(.dontSendTyping)
        case "messages.getSponsoredMessages":
            return get(.disableAds)
        case "channels.getChannelRecommendations":
            return get(.hideSimilarChannels)
        case "stories.getAllStories", "stories.getPeerMaxIDs", "stories.getPeerStories":
            return get(.disableStories)
        default:
            return false
        }
    }
}
