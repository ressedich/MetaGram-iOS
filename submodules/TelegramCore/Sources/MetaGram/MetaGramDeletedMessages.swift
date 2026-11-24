import Foundation
import Postbox

/// Marks a message that was deleted on the server but kept on this device
/// (MetaGram "Save Deleted Messages"). `date` is when the deletion arrived.
public final class MetaGramDeletedMessageAttribute: MessageAttribute {
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

public extension Message {
    /// When the message was deleted on the server, if MetaGram kept it.
    var metaGramDeletedDate: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? MetaGramDeletedMessageAttribute {
                return attribute.date
            }
        }
        return nil
    }
}

public extension EngineMessage {
    /// When the message was deleted on the server, if MetaGram kept it.
    var metaGramDeletedDate: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? MetaGramDeletedMessageAttribute {
                return attribute.date
            }
        }
        return nil
    }
}

enum MetaGramDeletedMessages {
    /// Called where the server's deletion of stored messages is applied (deletion updates, a history fill's
    /// confirmation, the account reset's ghost tail). Keeps the messages MetaGram must keep and returns the
    /// ids that are still to be deleted, in the order given.
    ///
    /// - A message already kept is never deleted by sync again (only by the user deleting it).
    /// - With "Save Deleted Messages" on, a stored cloud message is kept and marked deleted.
    static func filterDeletion(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
        let save = MetaGramSettings.get(.saveDeletedMessages)
        let now = Int32(Date().timeIntervalSince1970)
        var toDelete: [MessageId] = []
        for id in ids {
            guard let message = transaction.getMessage(id) else {
                toDelete.append(id)
                continue
            }
            if message.metaGramDeletedDate != nil {
                continue
            }
            if save && id.namespace == Namespaces.Message.Cloud {
                markDeleted(transaction: transaction, id: id, date: now)
            } else {
                toDelete.append(id)
            }
        }
        return toDelete
    }

    private static func markDeleted(transaction: Transaction, id: MessageId, date: Int32) {
        transaction.updateMessage(id, update: { currentMessage in
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = currentMessage.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
            }
            var attributes = currentMessage.attributes
            attributes.append(MetaGramDeletedMessageAttribute(date: date))
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
        })
    }
}
