import Foundation
import Display
import TelegramPresentationData
import AccountContext

// MetaGram's 20 app icons are the alternate icons of the app (metagram/ios_icons.py); they are
// chosen in Telegram's own picker in Settings > Appearance, which this opens at the icon row.

func metaGramCurrentIconTitle(strings: PresentationStrings) -> String {
    return ""
}

func metaGramAppIconController(context: AccountContext, updated: @escaping () -> Void) -> ViewController {
    return themeSettingsController(context: context, focusOnItemTag: .icon)
}
