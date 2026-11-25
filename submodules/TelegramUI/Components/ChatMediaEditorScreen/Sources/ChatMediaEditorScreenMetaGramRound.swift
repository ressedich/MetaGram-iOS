import Foundation
import UIKit
import Display
import Photos
import TelegramCore

/// MetaGram "Send as Video Message" from the media editor: the chat that opened the attachment menu sets `send`, which
/// sends a gallery video as a round video message (cropped to a square, up to 60 s).
public enum MetaGramRoundVideoHook {
    public static var send: ((PHAsset) -> Void)?
}

private let metaGramRoundButtonBackground: UIImage? = generateImage(CGSize(width: chatMediaEditorMuteButtonSize, height: chatMediaEditorMuteButtonSize), rotatedContext: { size, context in
    context.clear(CGRect(origin: .zero, size: size))
    context.setFillColor(UIColor(white: 0.0, alpha: 0.3).cgColor)
    context.fillEllipse(in: CGRect(origin: .zero, size: size))
})

/// The glyph: a ring with a dot, as a round video message.
private let metaGramRoundButtonIcon: UIImage? = generateImage(CGSize(width: 24.0, height: 24.0), rotatedContext: { size, context in
    context.clear(CGRect(origin: .zero, size: size))
    context.setStrokeColor(UIColor.white.cgColor)
    context.setLineWidth(2.0)
    context.strokeEllipse(in: CGRect(x: 2.0, y: 2.0, width: 20.0, height: 20.0))
    context.setFillColor(UIColor.white.cgColor)
    context.fillEllipse(in: CGRect(x: 8.0, y: 8.0, width: 8.0, height: 8.0))
})

extension ChatMediaEditorScreen.Node {
    /// The current item's video, when it can be sent as a round video message.
    var metaGramRoundAsset: PHAsset? {
        guard MetaGramSettings.get(.sendVideoAsRound), MetaGramRoundVideoHook.send != nil, self.isMuteButtonVisible else {
            return nil
        }
        guard case let .asset(asset) = self.pageModel.currentItem.source, asset.mediaType == .video else {
            return nil
        }
        return asset
    }

    /// Next to the mute button (the third slot, clear of the button beside it), shown and hidden with it.
    func metaGramUpdateRoundButton(transition: ContainedViewLayoutTransition) {
        guard self.metaGramRoundAsset != nil, let muteButton = self.muteButton else {
            self.metaGramRoundButton?.removeFromSuperview()
            self.metaGramRoundButton = nil
            return
        }
        let button: UIButton
        if let current = self.metaGramRoundButton {
            button = current
        } else {
            button = UIButton(type: .custom)
            button.setBackgroundImage(metaGramRoundButtonBackground, for: .normal)
            button.setImage(metaGramRoundButtonIcon, for: .normal)
            button.addTarget(self, action: #selector(self.metaGramRoundButtonPressed), for: .touchUpInside)
            self.metaGramRoundButton = button
            self.view.insertSubview(button, aboveSubview: muteButton)
            button.frame = muteButton.frame.offsetBy(dx: 2.0 * (chatMediaEditorMuteButtonSize + 8.0), dy: 0.0)
        }
        transition.updateFrame(view: button, frame: muteButton.frame.offsetBy(dx: 2.0 * (chatMediaEditorMuteButtonSize + 8.0), dy: 0.0))
        transition.updateAlpha(layer: button.layer, alpha: muteButton.alpha)
        button.isUserInteractionEnabled = muteButton.isUserInteractionEnabled
    }

    @objc func metaGramRoundButtonPressed() {
        guard let asset = self.metaGramRoundAsset, let send = MetaGramRoundVideoHook.send, !self.isSending, !self.isInvalidated else {
            return
        }
        send(asset)
        self.controller?.dismissAfterGallerySend()
    }
}
