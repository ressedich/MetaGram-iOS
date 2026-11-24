import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

enum MetaGramSend {
    /// Applies MetaGram's send options to outgoing messages ("Send without Sound").
    static func prepare(_ messages: [EnqueueMessage]) -> [EnqueueMessage] {
        guard MetaGramSettings.get(.sendWithoutSound) else {
            return messages
        }
        return messages.map { message -> EnqueueMessage in
            return message.withUpdatedAttributes { attributes -> [MessageAttribute] in
                if attributes.contains(where: { $0 is NotificationInfoMessageAttribute }) {
                    return attributes
                }
                var attributes = attributes
                attributes.append(NotificationInfoMessageAttribute(flags: .muted))
                return attributes
            }
        }
    }
}

public enum MetaGramReadOnInteract {
    /// "Read on Interact": while messages are not being read, sending a message or a reaction to a chat
    /// still marks that chat read on the server, as replying would in a normal client.
    public static func readChat(account: Account, peerId: PeerId) {
        guard MetaGramSettings.get(.dontReadMessages), MetaGramSettings.get(.readOnInteract) else {
            return
        }
        let signal = account.postbox.transaction { transaction -> (Peer?, MessageId?) in
            return (transaction.getPeer(peerId), transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud))
        }
        |> mapToSignal { peer, topId -> Signal<Never, NoError> in
            guard let peer = peer, let topId = topId else {
                return .complete()
            }
            MetaGramSettings.allowReadingBriefly()
            if peer is TelegramChannel, let inputChannel = apiInputChannel(peer) {
                return account.network.request(Api.functions.channels.readHistory(channel: inputChannel, maxId: topId.id))
                |> `catch` { _ -> Signal<Api.Bool, NoError> in
                    return .complete()
                }
                |> ignoreValues
            } else if let inputPeer = apiInputPeer(peer) {
                return account.network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: topId.id))
                |> `catch` { _ -> Signal<Api.messages.AffectedMessages, NoError> in
                    return .complete()
                }
                |> ignoreValues
            } else {
                return .complete()
            }
        }
        let _ = signal.startStandalone()
    }
}
