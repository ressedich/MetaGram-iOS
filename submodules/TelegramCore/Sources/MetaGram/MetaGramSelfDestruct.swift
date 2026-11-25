import Foundation
import Postbox

/// MetaGram "Keep Self-Destructing Media", as AyuGram does it: a self-destructing or view-once photo, video, voice or
/// round video in a cloud chat can be opened any number of times. Opening it does not consume it
/// (`MarkMessageContentAsConsumedInteractively`), so the server starts no timer and the sender sees it unopened; the
/// message menu's "Burn" consumes it on purpose.
///
/// If it is consumed anyway (burned, or opened on another device), the media stays viewable after its timer runs out.
/// The client normally replaces such media with "expired" placeholders in three places: when it is opened
/// (`MarkMessageContentAsConsumedInteractively`), when its timer fires (`ManagedAutoremoveMessageOperations`), and when
/// the server sends the message again without its media (edit updates, history validation). With the option on, the
/// first two keep the media, the timer one also drops the self-destruct timer so the message becomes ordinary media,
/// and the server's version keeps the stored media. Secret chats are not affected: their messages are deleted, not
/// expired. Only what was downloaded before it expired can be shown again.
enum MetaGramSelfDestruct {
    static var isEnabled: Bool {
        return MetaGramSettings.get(.keepSelfDestructingMedia)
    }

    static func isKept(peerId: PeerId) -> Bool {
        return self.isEnabled && peerId.namespace != Namespaces.Peer.SecretChat
    }

    /// `attributes` without self-destruct timers.
    static func attributesWithoutTimers(_ attributes: [MessageAttribute]) -> [MessageAttribute] {
        return attributes.filter { attribute in
            return !(attribute is AutoclearTimeoutMessageAttribute)
        }
    }

    /// Whether opening `message` must leave it unopened: incoming self-destructing media in a cloud chat while the
    /// option is on.
    static func keepsUnburned(_ message: Message) -> Bool {
        guard self.isKept(peerId: message.id.peerId), message.flags.contains(.Incoming) else {
            return false
        }
        return message.attributes.contains(where: { $0 is AutoclearTimeoutMessageAttribute }) && self.hasKeepableMedia(message.media)
    }

    /// Incoming self-destructing media in a cloud chat, while the option is on, is shown and handled as ordinary media.
    static func showsAsOrdinaryMedia(_ message: Message) -> Bool {
        return self.isKept(peerId: message.id.peerId) && message.flags.contains(.Incoming)
    }

    static func hasKeepableMedia(_ media: [Media]) -> Bool {
        return media.contains(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile })
    }

    /// The server's version of a stored message: when it expires media this device still has, the stored media stays,
    /// as ordinary media.
    static func keepingMedia(previous: Message, updated: StoreMessage) -> StoreMessage {
        guard self.isKept(peerId: previous.id.peerId) else {
            return updated
        }
        guard updated.media.contains(where: { $0 is TelegramMediaExpiredContent }), self.hasKeepableMedia(previous.media) else {
            return updated
        }
        return updated.withUpdatedMedia(previous.media).withUpdatedAttributes(self.attributesWithoutTimers(updated.attributes))
    }
}
