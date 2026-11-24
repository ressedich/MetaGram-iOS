import Foundation
import Display
import SwiftSignalKit
import AccountContext
import PresentationDataUtils

/// MetaGram "Send Confirmations": asks before a sticker or a GIF is sent.
enum MetaGramSendConfirmation {
    /// Set while a confirmed send runs again through the same handler, so it is not asked twice.
    private static let confirmed = Atomic<Bool>(value: false)

    static var isConfirmed: Bool {
        return confirmed.with { $0 }
    }

    static func runConfirmed(_ f: () -> Void) {
        let _ = confirmed.swap(true)
        f()
        let _ = confirmed.swap(false)
    }

    static func present(context: AccountContext, controller: ViewController, en: String, ru: String, confirm: @escaping () -> Void) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        controller.present(textAlertController(context: context, title: nil, text: isRussian ? ru : en, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: isRussian ? "Отправить" : "Send", action: confirm)
        ]), in: .window(.root))
    }
}
