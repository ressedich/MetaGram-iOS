import Foundation
import Postbox

/// One event of a chat's "MetaGram Logs".
public struct MetaGramLogEvent: Codable, Equatable {
    public enum Kind: Int32, Codable {
        /// A message was deleted by the other side.
        case messageDeleted = 0
        /// A message was edited by the other side.
        case messageEdited = 1
        /// The user changed their name.
        case nameChanged = 2
        /// The user changed their username.
        case usernameChanged = 3
        /// The user set, changed or removed their profile photo.
        case photoChanged = 4
    }

    /// When it happened (when it reached this device).
    public let date: Int32
    public let kind: Kind
    /// The message, for message events (cloud namespace, in this chat).
    public let messageId: Int32?
    /// Who did it, for message events in groups.
    public let authorId: Int64?
    /// The text before (a message's text, a name, a username), if any.
    public let oldValue: String?
    /// The text after, if any.
    public let newValue: String?
    /// For message events: the kind of media the message had ("photo", "video", "gif", "voice", "round", "sticker",
    /// "file"), if any.
    public let mediaKind: String?

    public init(date: Int32, kind: Kind, messageId: Int32?, authorId: Int64?, oldValue: String?, newValue: String?, mediaKind: String?) {
        self.date = date
        self.kind = kind
        self.messageId = messageId
        self.authorId = authorId
        self.oldValue = oldValue
        self.newValue = newValue
        self.mediaKind = mediaKind
    }
}

/// The logs of all chats of one account, in one JSON file beside its media (`metagram-event-log.json`), like the edit
/// history: what reached this device while the option was on, never rebuilt from the server.
final class MetaGramEventLogStore {
    static let shared = MetaGramEventLogStore()

    private let lock = NSLock()
    private var loaded: [String: [String: [MetaGramLogEvent]]] = [:]

    private static let fileName = "metagram-event-log.json"
    /// Bounds the file: older events beyond this, per chat, are dropped.
    private static let maxEventsPerChat = 500

    private static func key(_ peerId: PeerId) -> String {
        return "\(peerId.toInt64())"
    }

    private static func path(_ basePath: String) -> String {
        return basePath + "/" + fileName
    }

    /// Requires `lock`.
    private func table(_ basePath: String) -> [String: [MetaGramLogEvent]] {
        if let table = self.loaded[basePath] {
            return table
        }
        var table: [String: [MetaGramLogEvent]] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: MetaGramEventLogStore.path(basePath))), let decoded = try? JSONDecoder().decode([String: [MetaGramLogEvent]].self, from: data) {
            table = decoded
        }
        self.loaded[basePath] = table
        return table
    }

    /// Requires `lock`.
    private func store(_ table: [String: [MetaGramLogEvent]], basePath: String) {
        self.loaded[basePath] = table
        // the table is a value: the write encodes this version, off the caller's queue
        MetaGramFileWriter.shared.schedule(path: MetaGramEventLogStore.path(basePath), makeData: {
            return try? JSONEncoder().encode(table)
        })
    }

    func events(basePath: String, peerId: PeerId) -> [MetaGramLogEvent] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.table(basePath)[MetaGramEventLogStore.key(peerId)] ?? []
    }

    func append(basePath: String, events: [(PeerId, MetaGramLogEvent)]) {
        if events.isEmpty {
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        var table = self.table(basePath)
        for (peerId, event) in events {
            let key = MetaGramEventLogStore.key(peerId)
            var list = table[key] ?? []
            list.append(event)
            if list.count > MetaGramEventLogStore.maxEventsPerChat {
                list.removeFirst(list.count - MetaGramEventLogStore.maxEventsPerChat)
            }
            table[key] = list
        }
        self.store(table, basePath: basePath)
    }

    func clear(basePath: String, peerId: PeerId) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var table = self.table(basePath)
        table.removeValue(forKey: MetaGramEventLogStore.key(peerId))
        self.store(table, basePath: basePath)
    }
}

enum MetaGramEventLog {
    static var isEnabled: Bool {
        return MetaGramSettings.get(.eventLog)
    }

    private static var now: Int32 {
        return Int32(Date().timeIntervalSince1970)
    }

    static func mediaKind(_ media: [Media]) -> String? {
        for media in media {
            if media is TelegramMediaImage {
                return "photo"
            } else if let file = media as? TelegramMediaFile {
                if file.isSticker || file.isCustomEmoji {
                    return "sticker"
                } else if file.isInstantVideo {
                    return "round"
                } else if file.isVoice {
                    return "voice"
                } else if file.isAnimated {
                    return "gif"
                } else if file.isVideo {
                    return "video"
                } else {
                    return "file"
                }
            }
        }
        return nil
    }

    /// Messages deleted on the server (called where MetaGram filters such deletions): the other side's, in cloud chats.
    static func recordDeletions(transaction: Transaction, messages: [Message]) {
        guard self.isEnabled, let basePath = transaction.metaGramMediaBasePath else {
            return
        }
        let date = self.now
        var events: [(PeerId, MetaGramLogEvent)] = []
        for message in messages {
            guard message.flags.contains(.Incoming), message.id.namespace == Namespaces.Message.Cloud, message.id.peerId.namespace != Namespaces.Peer.SecretChat else {
                continue
            }
            events.append((message.id.peerId, MetaGramLogEvent(date: date, kind: .messageDeleted, messageId: message.id.id, authorId: message.author?.id.toInt64(), oldValue: message.text.isEmpty ? nil : message.text, newValue: nil, mediaKind: self.mediaKind(message.media))))
        }
        MetaGramEventLogStore.shared.append(basePath: basePath, events: events)
    }

    /// A server edit of a stored message.
    static func recordEdit(basePath: String, previous: Message, newText: String) {
        guard self.isEnabled, previous.flags.contains(.Incoming), previous.id.namespace == Namespaces.Message.Cloud, previous.text != newText else {
            return
        }
        MetaGramEventLogStore.shared.append(basePath: basePath, events: [(previous.id.peerId, MetaGramLogEvent(date: self.now, kind: .messageEdited, messageId: previous.id.id, authorId: previous.author?.id.toInt64(), oldValue: previous.text, newValue: newText, mediaKind: self.mediaKind(previous.media)))])
    }

    /// A user stored again with new data: their name, username and photo changes, logged in their private chat.
    static func recordUserUpdate(transaction: Transaction, previous: TelegramUser, updated: TelegramUser) {
        guard self.isEnabled, previous.id.namespace == Namespaces.Peer.CloudUser, !MetaGramSettings.isAccountPeer(previous.id.toInt64()) else {
            return
        }
        if previous.botInfo != nil {
            return
        }
        let date = self.now
        var events: [MetaGramLogEvent] = []
        let previousName = [previous.firstName, previous.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let updatedName = [updated.firstName, updated.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !previousName.isEmpty, !updatedName.isEmpty, previousName != updatedName {
            events.append(MetaGramLogEvent(date: date, kind: .nameChanged, messageId: nil, authorId: nil, oldValue: previousName, newValue: updatedName, mediaKind: nil))
        }
        if previous.addressName != updated.addressName {
            events.append(MetaGramLogEvent(date: date, kind: .usernameChanged, messageId: nil, authorId: nil, oldValue: previous.addressName, newValue: updated.addressName, mediaKind: nil))
        }
        let previousPhotoId = previous.photo.compactMap { ($0.resource as? CloudPeerPhotoSizeMediaResource)?.photoId }.first
        let updatedPhotoId = updated.photo.compactMap { ($0.resource as? CloudPeerPhotoSizeMediaResource)?.photoId }.first
        if previousPhotoId != updatedPhotoId, previousPhotoId != nil || updatedPhotoId != nil {
            let kind: String
            if previousPhotoId == nil {
                kind = "set"
            } else if updatedPhotoId == nil {
                kind = "removed"
            } else {
                kind = "changed"
            }
            events.append(MetaGramLogEvent(date: date, kind: .photoChanged, messageId: nil, authorId: nil, oldValue: nil, newValue: kind, mediaKind: nil))
        }
        if events.isEmpty {
            return
        }
        guard let basePath = transaction.metaGramMediaBasePath else {
            return
        }
        MetaGramEventLogStore.shared.append(basePath: basePath, events: events.map { (previous.id, $0) })
    }
}

public extension TelegramEngine.Messages {
    /// The chat's MetaGram Logs, oldest first.
    func metaGramEventLog(peerId: EnginePeer.Id) -> [MetaGramLogEvent] {
        return MetaGramEventLogStore.shared.events(basePath: self.account.postbox.mediaBox.basePath, peerId: peerId)
    }

    func clearMetaGramEventLog(peerId: EnginePeer.Id) {
        MetaGramEventLogStore.shared.clear(basePath: self.account.postbox.mediaBox.basePath, peerId: peerId)
    }
}
