import Foundation
import Postbox
import SwiftSignalKit

/// Forwarding from chats with "Restrict saving content", as AyuGram does it.
///
/// The server refuses to forward a protected message (`CHAT_FORWARDS_RESTRICTED`) and to send its media again by id, so
/// while `MetaGramSettings.bypassCopyProtection` is on, a forward of such a message is sent as a new message instead:
/// its text and entities are copied, and its photo or file is downloaded first and attached as a local file, which the
/// sender then uploads as new media. Stickers and custom emoji are not protected and are sent by id. Albums stay albums.
///
/// A message that cannot be copied (a poll, a game, media that fails to download, nothing left to send) stays a plain
/// forward, so the result keeps one entry per requested message.
enum MetaGramProtectedForward {
    static func prepare(account: Account, peerId: PeerId, messages: [EnqueueMessage]) -> Signal<[EnqueueMessage], NoError> {
        guard MetaGramSettings.isCopyProtectionBypassed else {
            return .single(messages)
        }
        let hasForwards = messages.contains(where: { message in
            if case .forward = message {
                return true
            }
            return false
        })
        if !hasForwards {
            return .single(messages)
        }

        return account.postbox.transaction { transaction -> [Message?] in
            return messages.map { message -> Message? in
                guard case let .forward(sourceId, _, _, _, _) = message, sourceId.namespace == Namespaces.Message.Cloud, let source = transaction.getMessage(sourceId) else {
                    return nil
                }
                return MetaGramProtectedForward.isProtected(transaction: transaction, message: source) ? source : nil
            }
        }
        |> mapToSignal { sources -> Signal<[EnqueueMessage], NoError> in
            if sources.allSatisfy({ $0 == nil }) {
                return .single(messages)
            }
            var groupingKeys: [Int64: Int64] = [:]
            var signals: [Signal<EnqueueMessage, NoError>] = []
            for (index, message) in messages.enumerated() {
                if let source = sources[index], case let .forward(_, threadId, grouping, forwardAttributes, correlationId) = message {
                    let localGroupingKey = forwardGroupingKey(grouping: grouping, sourceGroupingKey: source.groupingKey, generatedKeys: &groupingKeys)
                    signals.append(MetaGramProtectedForward.copiedMessage(account: account, peerId: peerId, source: source, threadId: threadId, forwardAttributes: forwardAttributes, localGroupingKey: localGroupingKey, correlationId: correlationId)
                    |> map { copied -> EnqueueMessage in
                        return copied ?? message
                    })
                } else {
                    signals.append(.single(message))
                }
            }
            return combineLatest(signals)
            |> take(1)
        }
    }

    /// Whether the server forbids forwarding `message`: the message itself, its chat, or a private chat in which either
    /// side turned on "Restrict saving content".
    private static func isProtected(transaction: Transaction, message: Message) -> Bool {
        if message.isServerCopyProtected() {
            return true
        }
        if message.id.peerId.namespace == Namespaces.Peer.CloudUser, let cachedData = transaction.getPeerCachedData(peerId: message.id.peerId) as? CachedUserData {
            return cachedData.flags.contains(.copyProtectionEnabled) || cachedData.flags.contains(.myCopyProtectionEnabled)
        }
        return false
    }

    private static func copiedMessage(account: Account, peerId: PeerId, source: Message, threadId: Int64?, forwardAttributes: [MessageAttribute], localGroupingKey: Int64?, correlationId: Int64?) -> Signal<EnqueueMessage?, NoError> {
        var sourceMedia: Media?
        for media in source.media {
            if media is TelegramMediaWebpage {
                // the server builds the link preview again from the text
                continue
            }
            sourceMedia = media
            break
        }

        let hidesCaption = sourceMedia != nil && forwardAttributes.contains(where: { ($0 as? ForwardOptionsMessageAttribute)?.hideCaptions == true })
        let text = hidesCaption ? "" : source.text

        var attributes: [MessageAttribute] = source.attributes.filter { attribute in
            switch attribute {
            case _ as TextEntitiesMessageAttribute:
                return !hidesCaption
            case _ as MediaSpoilerMessageAttribute, _ as InvertMediaMessageAttribute:
                return true
            default:
                return false
            }
        }
        attributes.append(contentsOf: forwardAttributes.filter { !($0 is ForwardOptionsMessageAttribute) })

        let media: Signal<AnyMediaReference?, NoError>
        let mediaIsRequired: Bool
        if let sourceMedia {
            mediaIsRequired = true
            media = copiedMedia(account: account, source: source, media: sourceMedia)
        } else {
            mediaIsRequired = false
            media = .single(nil)
        }

        return media
        |> map { mediaReference -> EnqueueMessage? in
            if mediaIsRequired && mediaReference == nil {
                return nil
            }
            if mediaReference == nil && text.isEmpty {
                return nil
            }
            let replyToMessageId = threadId.flatMap { threadId -> EngineMessageReplySubject in
                return EngineMessageReplySubject(messageId: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: threadId)), quote: nil, innerSubject: nil)
            }
            return .message(text: text, attributes: attributes, inlineStickers: [:], mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: nil, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: [])
        }
    }

    /// The media to attach to the copy, or nil when it cannot be copied.
    private static func copiedMedia(account: Account, source: Message, media: Media) -> Signal<AnyMediaReference?, NoError> {
        if let image = media as? TelegramMediaImage {
            guard let largest = largestImageRepresentation(image.representations) else {
                return .single(nil)
            }
            return downloadedLocalCopy(account: account, source: source, media: image, resource: largest.resource, contentType: .image)
            |> map { resource -> AnyMediaReference? in
                guard let resource else {
                    return nil
                }
                let copy = TelegramMediaImage(
                    imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)),
                    representations: [TelegramMediaImageRepresentation(dimensions: largest.dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: nil)],
                    immediateThumbnailData: image.immediateThumbnailData,
                    reference: nil,
                    partialReference: nil,
                    flags: []
                )
                return AnyMediaReference.standalone(media: copy)
            }
        } else if let file = media as? TelegramMediaFile {
            if file.isSticker || file.isCustomEmoji {
                // stickers are public: they are sent by id
                return .single(AnyMediaReference.message(message: MessageReference(source), media: file))
            }
            let contentType: MediaResourceUserContentType
            if file.isInstantVideo {
                contentType = .audioVideoMessage
            } else if file.isVoice {
                contentType = .audio
            } else if file.isVideo {
                contentType = .video
            } else {
                contentType = .file
            }
            let previewSignal: Signal<[TelegramMediaImageRepresentation], NoError>
            if let preview = largestImageRepresentation(file.previewRepresentations) {
                previewSignal = downloadedLocalCopy(account: account, source: source, media: file, resource: preview.resource, contentType: .image)
                |> map { resource -> [TelegramMediaImageRepresentation] in
                    guard let resource else {
                        return []
                    }
                    return [TelegramMediaImageRepresentation(dimensions: preview.dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: nil)]
                }
            } else {
                previewSignal = .single([])
            }
            return combineLatest(
                downloadedLocalCopy(account: account, source: source, media: file, resource: file.resource, contentType: contentType),
                previewSignal
            )
            |> map { resource, previewRepresentations -> AnyMediaReference? in
                guard let resource else {
                    return nil
                }
                let copy = TelegramMediaFile(
                    fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)),
                    partialReference: nil,
                    resource: resource,
                    previewRepresentations: previewRepresentations,
                    videoThumbnails: [],
                    videoCover: nil,
                    immediateThumbnailData: file.immediateThumbnailData,
                    mimeType: file.mimeType,
                    size: resource.size ?? file.size,
                    attributes: file.attributes,
                    alternativeRepresentations: []
                )
                return AnyMediaReference.standalone(media: copy)
            }
        } else if media is TelegramMediaMap || media is TelegramMediaContact || media is TelegramMediaDice {
            return .single(AnyMediaReference.standalone(media: media))
        } else {
            return .single(nil)
        }
    }

    /// Downloads `resource` in full and copies it into a new local resource, which the sender uploads as a new file.
    /// Nil when the download fails.
    private static func downloadedLocalCopy(account: Account, source: Message, media: Media, resource: MediaResource, contentType: MediaResourceUserContentType) -> Signal<LocalFileMediaResource?, NoError> {
        let mediaBox = account.postbox.mediaBox
        let reference = AnyMediaReference.message(message: MessageReference(source), media: media).resourceReference(resource)
        return Signal<LocalFileMediaResource?, NoError> { subscriber in
            let fetchDisposable = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(source.id.peerId), userContentType: contentType, reference: reference).start(error: { _ in
                subscriber.putNext(nil)
                subscriber.putCompletion()
            })
            let dataDisposable = (mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
            |> filter { $0.complete }
            |> take(1)).start(next: { data in
                let localResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: data.size)
                mediaBox.copyResourceData(from: resource.id, to: localResource.id, synchronous: true)
                subscriber.putNext(localResource)
                subscriber.putCompletion()
            })
            return ActionDisposable {
                fetchDisposable.dispose()
                dataDisposable.dispose()
            }
        }
        |> take(1)
    }
}
