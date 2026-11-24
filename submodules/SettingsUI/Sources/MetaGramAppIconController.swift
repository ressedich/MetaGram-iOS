import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// The 20-icon picker for iOS is not wired yet (the icons must be added as alternate icons
// to the app bundle first); for now this screen says so.

func metaGramCurrentIconTitle(strings: PresentationStrings) -> String {
    return "MetaGram"
}

private enum MetaGramAppIconEntry: ItemListNodeEntry {
    case info(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        return 0
    }

    static func <(lhs: MetaGramAppIconEntry, rhs: MetaGramAppIconEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func metaGramAppIconController(context: AccountContext, updated: @escaping () -> Void) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let text = isRussian ? "Выбор из 20 иконок появится в следующей версии." : "Choosing from 20 icons comes in the next version."
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isRussian ? "Иконка приложения" : "App Icon"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: [MetaGramAppIconEntry.info(text)], style: .blocks, animateChanges: false)
        return (controllerState, (listState, 0))
    }
    return ItemListController(context: context, state: signal)
}
