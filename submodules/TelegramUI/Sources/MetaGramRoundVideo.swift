import Foundation
import UIKit
import AVFoundation
import Photos
import SwiftSignalKit
import TelegramCore
import AccountContext

/// MetaGram "Send as Video Message" (as Swiftgram): a video picked from the gallery is cropped to a centred square,
/// cut to the first 60 seconds (the longest a video message can be) and sent as a round video message.
enum MetaGramRoundVideo {
    static let side: CGFloat = 400.0
    static let maxDuration: Double = 60.0

    struct Exported {
        let path: String
        let duration: Double
        let thumbnail: UIImage?
    }

    /// Exports `asset` as a square round-video file; nil on failure. `completion` runs on the main queue.
    static func export(asset: PHAsset, completion: @escaping (Exported?) -> Void) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options, resultHandler: { avAsset, _, _ in
            guard let avAsset, let track = avAsset.tracks(withMediaType: .video).first else {
                Queue.mainQueue().async {
                    completion(nil)
                }
                return
            }

            let naturalRect = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
            let width = abs(naturalRect.width)
            let height = abs(naturalRect.height)
            let cropSide = min(width, height)
            guard cropSide > 0.0 else {
                Queue.mainQueue().async {
                    completion(nil)
                }
                return
            }
            let scale = MetaGramRoundVideo.side / cropSide

            // the oriented frame moved to the origin, its centred square moved to the origin, scaled to the output
            var transform = track.preferredTransform
            transform = transform.concatenating(CGAffineTransform(translationX: -naturalRect.minX, y: -naturalRect.minY))
            transform = transform.concatenating(CGAffineTransform(translationX: -(width - cropSide) / 2.0, y: -(height - cropSide) / 2.0))
            transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

            let duration = min(CMTimeGetSeconds(avAsset.duration), MetaGramRoundVideo.maxDuration)
            let timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layerInstruction.setTransform(transform, at: .zero)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = timeRange
            instruction.layerInstructions = [layerInstruction]
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CGSize(width: MetaGramRoundVideo.side, height: MetaGramRoundVideo.side)
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            videoComposition.instructions = [instruction]

            guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetHighestQuality) else {
                Queue.mainQueue().async {
                    completion(nil)
                }
                return
            }
            let path = NSTemporaryDirectory() + "metagram-round-\(Int64.random(in: 0 ... Int64.max)).mp4"
            exportSession.outputURL = URL(fileURLWithPath: path)
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true
            exportSession.timeRange = timeRange
            exportSession.videoComposition = videoComposition
            exportSession.exportAsynchronously {
                guard exportSession.status == .completed else {
                    Queue.mainQueue().async {
                        completion(nil)
                    }
                    return
                }
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
                generator.appliesPreferredTrackTransform = true
                let thumbnail = (try? generator.copyCGImage(at: .zero, actualTime: nil)).flatMap(UIImage.init(cgImage:))
                Queue.mainQueue().async {
                    completion(Exported(path: path, duration: duration, thumbnail: thumbnail))
                }
            }
        })
    }

    /// The video message for an exported file, its data moved into the media box.
    static func message(context: AccountContext, exported: Exported, threadId: Int64?) -> EnqueueMessage {
        let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
        context.engine.resources.moveResourceData(id: EngineMediaResource.Id(resource.id), fromTempPath: exported.path)

        var previewRepresentations: [TelegramMediaImageRepresentation] = []
        if let thumbnail = exported.thumbnail, let data = thumbnail.jpegData(compressionQuality: 0.6) {
            let thumbnailResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
            context.engine.resources.storeResourceData(id: EngineMediaResource.Id(thumbnailResource.id), data: data)
            previewRepresentations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: Int32(thumbnail.size.width), height: Int32(thumbnail.size.height)), resource: thumbnailResource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
        }

        let dimensions = PixelDimensions(width: Int32(MetaGramRoundVideo.side), height: Int32(MetaGramRoundVideo.side))
        let file = TelegramMediaFile(fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: previewRepresentations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: nil, attributes: [.FileName(fileName: "video.mp4"), .Video(duration: exported.duration, size: dimensions, flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: nil)], alternativeRepresentations: [])

        return .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: file), threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
    }
}

extension ChatControllerImpl {
    func metaGramSendVideoAsRound(asset: PHAsset) {
        MetaGramRoundVideo.export(asset: asset, completion: { [weak self] exported in
            guard let self, let exported else {
                return
            }
            self.sendMessages([MetaGramRoundVideo.message(context: self.context, exported: exported, threadId: self.chatLocation.threadId)])
        })
    }
}
