import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class MetaGramSettingsControllerArguments {
    let setGhostMode: (Bool) -> Void
    let setValue: (MetaGramSettings.Key, Bool) -> Void

    init(setGhostMode: @escaping (Bool) -> Void, setValue: @escaping (MetaGramSettings.Key, Bool) -> Void) {
        self.setGhostMode = setGhostMode
        self.setValue = setValue
    }
}

private enum MetaGramSettingsSection: Int32 {
    case ghost
    case spy
    case other
}

private struct MetaGramStrings {
    let isRussian: Bool

    init(_ strings: PresentationStrings) {
        self.isRussian = strings.baseLanguageCode.hasPrefix("ru")
    }

    func text(_ en: String, _ ru: String) -> String {
        return self.isRussian ? ru : en
    }
}

private enum MetaGramSettingsEntry: ItemListNodeEntry {
    case ghostHeader
    case ghostMode(Bool)
    case option(index: Int32, key: MetaGramSettings.Key, value: Bool)
    case ghostFooter
    case spyHeader
    case saveDeleted(Bool)
    case spyFooter
    case otherHeader
    case disableAds(Bool)

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostMode, .option, .ghostFooter:
            return MetaGramSettingsSection.ghost.rawValue
        case .spyHeader, .saveDeleted, .spyFooter:
            return MetaGramSettingsSection.spy.rawValue
        case .otherHeader, .disableAds:
            return MetaGramSettingsSection.other.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostHeader:
            return 0
        case .ghostMode:
            return 1
        case let .option(index, _, _):
            return 10 + index
        case .ghostFooter:
            return 50
        case .spyHeader:
            return 60
        case .saveDeleted:
            return 61
        case .spyFooter:
            return 62
        case .otherHeader:
            return 100
        case .disableAds:
            return 101
        }
    }

    static func <(lhs: MetaGramSettingsEntry, rhs: MetaGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    private static func title(_ key: MetaGramSettings.Key, _ s: MetaGramStrings) -> String {
        switch key {
        case .dontReadMessages:
            return s.text("Don't Read Messages", "Не читать сообщения")
        case .dontReadStories:
            return s.text("Don't Read Stories", "Не просматривать истории")
        case .dontSendOnline:
            return s.text("Don't Send Online", "Не отправлять «в сети»")
        case .dontSendTyping:
            return s.text("Don't Send Typing", "Не отправлять «печатает»")
        case .disableAds:
            return s.text("Disable Ads", "Отключить рекламу")
        case .saveDeletedMessages:
            return s.text("Save Deleted Messages", "Сохранять удалённые сообщения")
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MetaGramSettingsControllerArguments
        let s = MetaGramStrings(presentationData.strings)
        switch self {
        case .ghostHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: s.text("GHOST MODE", "РЕЖИМ ПРИЗРАКА"), sectionId: self.section)
        case let .ghostMode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: s.text("Ghost Mode", "Режим призрака"), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setGhostMode(value)
            })
        case let .option(_, key, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: MetaGramSettingsEntry.title(key, s), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setValue(key, value)
            })
        case .ghostFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(s.text(
                "Messages you read stay unread for the sender, and nobody sees you online or typing.",
                "Прочитанные вами сообщения остаются непрочитанными у отправителя, а «в сети» и «печатает» никто не видит."
            )), sectionId: self.section)
        case .spyHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: s.text("SPY ESSENTIALS", "СЛЕЖКА"), sectionId: self.section)
        case let .saveDeleted(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: MetaGramSettingsEntry.title(.saveDeletedMessages, s), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setValue(.saveDeletedMessages, value)
            })
        case .spyFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain(s.text(
                "Messages deleted by others stay in the chat marked \"deleted\". Only messages that reached this device before deletion can be kept.",
                "Сообщения, удалённые собеседником, остаются в чате с пометкой «удалено». Сохраняется только то, что успело прийти на устройство до удаления."
            )), sectionId: self.section)
        case .otherHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: s.text("OTHER", "ПРОЧЕЕ"), sectionId: self.section)
        case let .disableAds(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: MetaGramSettingsEntry.title(.disableAds, s), value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setValue(.disableAds, value)
            })
        }
    }
}

private func metaGramSettingsEntries() -> [MetaGramSettingsEntry] {
    var entries: [MetaGramSettingsEntry] = []
    entries.append(.ghostHeader)
    entries.append(.ghostMode(MetaGramSettings.isGhostModeEnabled))
    for (index, key) in MetaGramSettings.ghostKeys.enumerated() {
        entries.append(.option(index: Int32(index), key: key, value: MetaGramSettings.get(key)))
    }
    entries.append(.ghostFooter)
    entries.append(.spyHeader)
    entries.append(.saveDeleted(MetaGramSettings.get(.saveDeletedMessages)))
    entries.append(.spyFooter)
    entries.append(.otherHeader)
    entries.append(.disableAds(MetaGramSettings.get(.disableAds)))
    return entries
}

public func metaGramSettingsController(context: AccountContext) -> ViewController {
    // Settings live in UserDefaults; bumping this value redraws the list after a change.
    let revision = ValuePromise<Int32>(0, ignoreRepeated: false)
    let currentRevision = Atomic<Int32>(value: 0)
    let refresh: () -> Void = {
        revision.set(currentRevision.modify { $0 + 1 })
    }

    let arguments = MetaGramSettingsControllerArguments(
        setGhostMode: { value in
            MetaGramSettings.setGhostMode(value)
            refresh()
        },
        setValue: { key, value in
            MetaGramSettings.set(key, value)
            refresh()
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, revision.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("MetaGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: metaGramSettingsEntries(), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    return controller
}
