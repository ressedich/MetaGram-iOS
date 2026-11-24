import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

enum MetaGramSend {
    /// Applies MetaGram's send options to outgoing messages ("Send without Sound", "Delayed Send").
    static func prepare(_ messages: [EnqueueMessage], peerId: PeerId) -> [EnqueueMessage] {
        let withoutSound = MetaGramSettings.get(.sendWithoutSound)
        // secret chats have no scheduled messages
        let delayed = MetaGramSettings.get(.delayedSend) && peerId.namespace != Namespaces.Peer.SecretChat
        if !withoutSound && !delayed {
            return messages
        }
        let scheduleTime = Int32(Date().timeIntervalSince1970) + 12
        return messages.map { message -> EnqueueMessage in
            let delaysThis = delayed && canDelay(message)
            return message.withUpdatedAttributes { attributes -> [MessageAttribute] in
                var attributes = attributes
                if withoutSound && !attributes.contains(where: { $0 is NotificationInfoMessageAttribute }) {
                    attributes.append(NotificationInfoMessageAttribute(flags: .muted))
                }
                if delaysThis && !attributes.contains(where: { $0 is OutgoingScheduleInfoMessageAttribute }) {
                    attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: nil))
                }
                return attributes
            }
        }
    }

    /// "Delayed Send" schedules only plain text. Media is not delayed: its schedule time is fixed before the upload,
    /// which can take longer than the delay, and the server does not schedule self-destructing (view-once) media,
    /// so such messages arrived late or not at all. Forwards are not delayed either.
    private static func canDelay(_ message: EnqueueMessage) -> Bool {
        guard case let .message(_, attributes, _, mediaReference, _, _, _, _, _, _) = message else {
            return false
        }
        if mediaReference != nil {
            return false
        }
        if attributes.contains(where: { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute }) {
            return false
        }
        return true
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
