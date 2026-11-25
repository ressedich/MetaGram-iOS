import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext

/// MetaGram: saves a voice message or a round video, which Telegram itself does not let you save. The file is
/// downloaded if needed, copied to a temporary file with a proper extension and offered in the system share sheet
/// ("Save to Files", "Save Video", other apps).
enum MetaGramMediaExport {
    /// The voice message or round video of `message`, if it has one.
    static func exportableFile(_ message: EngineRawMessage) -> TelegramMediaFile? {
        for media in message.media {
            if let file = media as? TelegramMediaFile, file.isVoice || file.isInstantVideo {
                return file
            }
        }
        return nil
    }

    static func share(context: AccountContext, message: EngineRawMessage, file: TelegramMediaFile) {
        let resource = EngineMediaResource(file.resource)
        let reference = AnyMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource)
        let fetchDisposable = context.engine.resources.fetch(reference: reference, userLocation: .peer(message.id.peerId), userContentType: file.isVoice ? .audio : .audioVideoMessage).start()

        let fileExtension = file.isVoice ? "ogg" : "mp4"
        let prefix = file.isVoice ? "Voice" : "Video"
        let fileName = "\(prefix)-\(message.id.peerId.toInt64())-\(message.id.id).\(fileExtension)"

        let _ = (context.engine.resources.data(resource: resource)
        |> filter { $0.isComplete }
        |> take(1)
        |> deliverOnMainQueue).start(next: { data in
            fetchDisposable.dispose()
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
            let _ = try? FileManager.default.removeItem(at: url)
            do {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: data.path), to: url)
            } catch {
                return
            }
            let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            context.sharedContext.applicationBindings.presentNativeController(activityController)
        })
    }
}
