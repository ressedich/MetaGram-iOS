import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI

// MARK: - Strings

private struct MetaGramStrings {
    let isRussian: Bool

    init(_ strings: PresentationStrings) {
        self.isRussian = strings.baseLanguageCode.hasPrefix("ru")
    }

    func text(_ en: String, _ ru: String) -> String {
        return self.isRussian ? ru : en
    }
}

// MARK: - Catalog

private enum MetaGramSettingsAction: Equatable {
    case messageFilters
    case shadowBanned
    case appIcon
}

private struct MetaGramOption {
    let key: MetaGramSettings.Key
    let en: String
    let ru: String
}

private struct MetaGramActionOption {
    let action: MetaGramSettingsAction
    let en: String
    let ru: String
}

private struct MetaGramGroup {
    let en: String
    let ru: String
    var ghostMaster: Bool = false
    var options: [MetaGramOption] = []
    var actions: [MetaGramActionOption] = []
    var footerEn: String? = nil
    var footerRu: String? = nil
}

private let metaGramCatalog: [MetaGramGroup] = [
    MetaGramGroup(en: "GHOST MODE", ru: "РЕЖИМ ПРИЗРАКА", ghostMaster: true, options: [
        MetaGramOption(key: .dontReadMessages, en: "Don't Read Messages", ru: "Не читать сообщения"),
        MetaGramOption(key: .dontReadStories, en: "Don't Read Stories", ru: "Не просматривать истории"),
        MetaGramOption(key: .dontSendOnline, en: "Don't Send Online", ru: "Не отправлять «в сети»"),
        MetaGramOption(key: .dontSendTyping, en: "Don't Send Typing", ru: "Не отправлять «печатает»"),
        MetaGramOption(key: .goOfflineAutomatically, en: "Go Offline Automatically", ru: "Автоматически уходить в офлайн"),
        MetaGramOption(key: .readOnInteract, en: "Read on Interact", ru: "Читать при ответе"),
    ], footerEn: "Messages you read stay unread for the sender, and nobody sees you online or typing. \"Read on Interact\" marks a chat read when you reply or react in it.", footerRu: "Прочитанные сообщения остаются непрочитанными у отправителя, а «в сети» и «печатает» никто не видит. «Читать при ответе» отмечает чат прочитанным, когда вы отвечаете или ставите реакцию."),
    MetaGramGroup(en: "SENDING", ru: "ОТПРАВКА", options: [
        MetaGramOption(key: .sendWithoutSound, en: "Send without Sound", ru: "Отправлять без звука"),
        MetaGramOption(key: .delayedSend, en: "Delayed Send (~12 s)", ru: "Отложенная отправка (~12 с)"),
    ], footerEn: "Delayed Send holds text messages for about 12 seconds as scheduled messages, so they can still be cancelled. Media is sent at once.", footerRu: "Отложенная отправка держит текстовые сообщения около 12 секунд как запланированные — их ещё можно отменить. Медиа уходит сразу."),
    MetaGramGroup(en: "SAVING & LOGS", ru: "СОХРАНЕНИЕ И ЛОГИ", options: [
        MetaGramOption(key: .saveDeletedMessages, en: "Save Deleted Messages", ru: "Сохранять удалённые сообщения"),
        MetaGramOption(key: .saveInBotDialogs, en: "Save in Bot Dialogs", ru: "Сохранять в чатах с ботами"),
        MetaGramOption(key: .saveEditsHistory, en: "Save Edits History", ru: "Сохранять историю правок"),
        MetaGramOption(key: .keepClearedHistory, en: "Keep Cleared Chats", ru: "Не очищать чат у себя"),
        MetaGramOption(key: .keepSelfDestructingMedia, en: "Keep Self-Destructing Media", ru: "Сохранять исчезающие медиа"),
        MetaGramOption(key: .eventLog, en: "MetaGram Logs", ru: "Логи MetaGram"),
    ], footerEn: "Deleted messages stay in the chat marked \"deleted\"; earlier versions of edited ones are in the message menu. Self-destructing media opens any number of times and the sender sees it unopened; \"Burn Media\" in its menu opens it for real. MetaGram Logs in a profile list what that chat deleted, edited and changed. Only what reached this device is kept.", footerRu: "Удалённые сообщения остаются в чате с пометкой «удалено», прежние версии изменённых — в меню сообщения. Исчезающие медиа открываются сколько угодно раз, а отправитель видит их непросмотренными; «Сжечь медиа» в меню открывает по-настоящему. «Логи MetaGram» в профиле показывают, что в этом чате удаляли, правили и меняли. Сохраняется только то, что дошло до устройства."),
    MetaGramGroup(en: "CONTENT PROTECTION", ru: "ЗАЩИТА КОНТЕНТА", options: [
        MetaGramOption(key: .bypassCopyProtection, en: "Bypass Copy Protection", ru: "Обходить запрет пересылки"),
        MetaGramOption(key: .downloadStories, en: "Download Stories", ru: "Скачивание историй"),
    ], footerEn: "Protected chats can be forwarded, copied and saved: such messages are sent as your own, their media downloaded and uploaded again. Any story, protected ones too, can be saved from its menu.", footerRu: "Из защищённых чатов можно пересылать, копировать и сохранять: такие сообщения уходят как ваши, а медиа скачивается и загружается заново. Любую историю, в том числе защищённую, можно сохранить из её меню."),
    MetaGramGroup(en: "MEDIA", ru: "МЕДИА", options: [
        MetaGramOption(key: .speedBoost, en: "Speed Boost", ru: "Ускорение загрузки"),
        MetaGramOption(key: .sendVideoAsRound, en: "Send Video as Video Message", ru: "Видео из галереи кружком"),
    ], footerEn: "Speed Boost downloads and uploads files in more parallel parts. A video picked from the gallery can be sent as a round video message from the send button's menu. Voice and video messages can be saved from their menu.", footerRu: "Ускорение загружает и выгружает файлы большим числом параллельных частей. Видео из галереи можно отправить кружком из меню кнопки отправки. Голосовые и кружки сохраняются из меню сообщения."),
    MetaGramGroup(en: "CHATS", ru: "ЧАТЫ", options: [
        MetaGramOption(key: .showPeerId, en: "Show ID, DC and Registration", ru: "ID, DC и дата регистрации"),
        MetaGramOption(key: .showMessageSeconds, en: "Show Message Seconds", ru: "Секунды во времени сообщений"),
        MetaGramOption(key: .hideReactions, en: "Hide Reactions", ru: "Скрывать реакции"),
        MetaGramOption(key: .translucentDeleted, en: "Translucent Deleted Messages", ru: "Полупрозрачные удалённые"),
        MetaGramOption(key: .markWithIcons, en: "Replace Marks with Icons", ru: "Значки вместо пометок"),
        MetaGramOption(key: .disableGreetingSticker, en: "Disable Greeting Sticker", ru: "Без приветственного стикера"),
        MetaGramOption(key: .disableColorfulReplies, en: "Disable Colorful Replies", ru: "Без цветных ответов"),
    ], footerEn: "The profile shows the ID (tap to copy), the data center and an estimate of when the account was registered.", footerRu: "В профиле видны ID (нажмите, чтобы скопировать), дата-центр и примерная дата регистрации аккаунта."),
    MetaGramGroup(en: "SEND CONFIRMATIONS", ru: "ПОДТВЕРЖДЕНИЕ ОТПРАВКИ", options: [
        MetaGramOption(key: .confirmStickers, en: "Stickers", ru: "Стикеры"),
        MetaGramOption(key: .confirmGifs, en: "GIFs", ru: "GIF"),
        MetaGramOption(key: .confirmVoice, en: "Voice & Round Videos", ru: "Голосовые и кружки"),
    ]),
    MetaGramGroup(en: "APPEARANCE", ru: "ВНЕШНИЙ ВИД", options: [
        MetaGramOption(key: .streamerMode, en: "Streamer Mode", ru: "Режим стримера"),
        MetaGramOption(key: .hidePremiumStatuses, en: "Hide Premium Statuses", ru: "Скрывать Premium-статусы"),
        MetaGramOption(key: .hideNotificationCounters, en: "Hide Notification Counters", ru: "Скрывать счётчики"),
        MetaGramOption(key: .islandBadge, en: "Logo in Dynamic Island", ru: "Логотип в островке"),
    ], actions: [
        MetaGramActionOption(action: .appIcon, en: "App Icon", ru: "Иконка приложения"),
    ], footerEn: "Streamer Mode hides chat names and message previews in the chat list. On iPhones with the Dynamic Island, a Live Activity shows the MetaGram logo in the island while the app runs in the background.", footerRu: "Режим стримера скрывает названия чатов и тексты сообщений в списке чатов. На iPhone с островком Live Activity показывает логотип MetaGram в островке, пока приложение работает в фоне."),
    MetaGramGroup(en: "GENERAL", ru: "ОБЩЕЕ", options: [
        MetaGramOption(key: .disableStories, en: "Disable Stories", ru: "Отключить истории"),
        MetaGramOption(key: .hideSimilarChannels, en: "Disable Similar Channels", ru: "Без похожих каналов"),
        MetaGramOption(key: .disableLinkWarning, en: "Disable Open Link Warning", ru: "Без предупреждения о ссылках"),
        MetaGramOption(key: .filterZalgo, en: "Filter Zalgo", ru: "Фильтровать «залго»"),
        MetaGramOption(key: .spoofAndroid, en: "Spoof Client as Android", ru: "Маскироваться под Android"),
    ]),
    MetaGramGroup(en: "FILTERS", ru: "ФИЛЬТРЫ", options: [
        MetaGramOption(key: .enableFilters, en: "Enable Filters", ru: "Включить фильтры"),
        MetaGramOption(key: .hideFromBlocked, en: "Hide from Blocked Users", ru: "Скрывать от заблокированных"),
    ], actions: [
        MetaGramActionOption(action: .messageFilters, en: "Message Filters", ru: "Фильтры сообщений"),
        MetaGramActionOption(action: .shadowBanned, en: "Shadow Ban", ru: "Теневой бан"),
    ], footerEn: "Messages matching a filter (regular expression) or sent by a shadow-banned user are hidden. Shadow-ban a user from their message menu.", footerRu: "Сообщения, подходящие под фильтр (регулярное выражение) или от пользователя в теневом бане, скрываются. В теневой бан добавляют через меню сообщения."),
    MetaGramGroup(en: "OTHER", ru: "ПРОЧЕЕ", options: [
        MetaGramOption(key: .disableAds, en: "Disable Ads", ru: "Отключить рекламу"),
        MetaGramOption(key: .localPremium, en: "Local Telegram Premium", ru: "Локальный Telegram Premium"),
    ], footerEn: "Local Premium unlocks Premium features that work on this device only; the server still sees a regular account.", footerRu: "Локальный Premium открывает функции Premium, которые работают только на этом устройстве: для сервера аккаунт остаётся обычным."),
]

// MARK: - List

private final class MetaGramSettingsControllerArguments {
    let setGhostMode: (Bool) -> Void
    let setValue: (MetaGramSettings.Key, Bool) -> Void
    let open: (MetaGramSettingsAction) -> Void

    init(setGhostMode: @escaping (Bool) -> Void, setValue: @escaping (MetaGramSettings.Key, Bool) -> Void, open: @escaping (MetaGramSettingsAction) -> Void) {
        self.setGhostMode = setGhostMode
        self.setValue = setValue
        self.open = open
    }
}

private enum MetaGramSettingsEntry: ItemListNodeEntry {
    case header(id: Int32, section: Int32, text: String)
    case ghostMode(id: Int32, section: Int32, title: String, value: Bool)
    case toggle(id: Int32, section: Int32, key: MetaGramSettings.Key, title: String, value: Bool)
    case action(id: Int32, section: Int32, action: MetaGramSettingsAction, title: String, label: String)
    case footer(id: Int32, section: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .footer(_, section, _):
            return section
        case let .ghostMode(_, section, _, _):
            return section
        case let .toggle(_, section, _, _, _):
            return section
        case let .action(_, section, _, _, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .footer(id, _, _):
            return id
        case let .ghostMode(id, _, _, _):
            return id
        case let .toggle(id, _, _, _, _):
            return id
        case let .action(id, _, _, _, _):
            return id
        }
    }

    static func <(lhs: MetaGramSettingsEntry, rhs: MetaGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MetaGramSettingsControllerArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ghostMode(_, _, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setGhostMode(value)
            })
        case let .toggle(_, _, key, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setValue(key, value)
            })
        case let .action(_, _, action, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.open(action)
            })
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func metaGramSettingsEntries(strings: PresentationStrings) -> [MetaGramSettingsEntry] {
    let s = MetaGramStrings(strings)
    var entries: [MetaGramSettingsEntry] = []
    var nextId: Int32 = 0
    for (sectionIndex, group) in metaGramCatalog.enumerated() {
        let section = Int32(sectionIndex)
        entries.append(.header(id: nextId, section: section, text: s.text(group.en, group.ru)))
        nextId += 1
        if group.ghostMaster {
            entries.append(.ghostMode(id: nextId, section: section, title: s.text("Ghost Mode", "Режим призрака"), value: MetaGramSettings.isGhostModeEnabled))
            nextId += 1
        }
        for option in group.options {
            entries.append(.toggle(id: nextId, section: section, key: option.key, title: s.text(option.en, option.ru), value: MetaGramSettings.get(option.key)))
            nextId += 1
        }
        for option in group.actions {
            let label: String
            switch option.action {
            case .messageFilters:
                label = "\(MetaGramSettings.list(.messageFilters).count)"
            case .shadowBanned:
                label = "\(MetaGramSettings.list(.shadowBanned).count)"
            case .appIcon:
                label = metaGramCurrentIconTitle(strings: strings)
            }
            entries.append(.action(id: nextId, section: section, action: option.action, title: s.text(option.en, option.ru), label: label))
            nextId += 1
        }
        if let footerEn = group.footerEn, let footerRu = group.footerRu {
            entries.append(.footer(id: nextId, section: section, text: s.text(footerEn, footerRu)))
            nextId += 1
        }
    }
    return entries
}

public func metaGramSettingsController(context: AccountContext) -> ViewController {
    // Settings live in UserDefaults; bumping this value redraws the list after a change.
    let revision = ValuePromise<Int32>(0, ignoreRepeated: false)
    let currentRevision = Atomic<Int32>(value: 0)
    let refresh: () -> Void = {
        revision.set(currentRevision.modify { $0 + 1 })
    }

    var pushImpl: ((ViewController) -> Void)?

    let arguments = MetaGramSettingsControllerArguments(
        setGhostMode: { value in
            MetaGramSettings.setGhostMode(value)
            refresh()
        },
        setValue: { key, value in
            MetaGramSettings.set(key, value)
            if key == .islandBadge {
                MetaGramLiveActivity.update()
            }
            refresh()
        },
        open: { action in
            switch action {
            case .messageFilters:
                pushImpl?(metaGramMessageFiltersController(context: context, updated: refresh))
            case .shadowBanned:
                pushImpl?(metaGramShadowBanController(context: context, updated: refresh))
            case .appIcon:
                pushImpl?(metaGramAppIconController(context: context, updated: refresh))
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, revision.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("MetaGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: metaGramSettingsEntries(strings: presentationData.strings), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}

// MARK: - Message filters editor

private enum MetaGramListEntry: ItemListNodeEntry {
    case add(id: Int32, title: String)
    case item(id: Int32, index: Int, title: String, label: String)
    case footer(id: Int32, text: String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .add(id, _), let .footer(id, _):
            return id
        case let .item(id, _, _, _):
            return id
        }
    }

    static func <(lhs: MetaGramListEntry, rhs: MetaGramListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MetaGramListArguments
        switch self {
        case let .add(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case let .item(_, index, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.open(index)
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class MetaGramListArguments {
    let add: () -> Void
    let open: (Int) -> Void

    init(add: @escaping () -> Void, open: @escaping (Int) -> Void) {
        self.add = add
        self.open = open
    }
}

private func metaGramMessageFiltersController(context: AccountContext, updated: @escaping () -> Void) -> ViewController {
    let revision = ValuePromise<Int32>(0, ignoreRepeated: false)
    let currentRevision = Atomic<Int32>(value: 0)
    let refresh: () -> Void = {
        revision.set(currentRevision.modify { $0 + 1 })
        updated()
    }

    var presentImpl: ((ViewController) -> Void)?

    let edit: (Int?) -> Void = { index in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let s = MetaGramStrings(presentationData.strings)
        var patterns = MetaGramSettings.list(.messageFilters)
        let current: String? = index.flatMap { $0 < patterns.count ? patterns[$0] : nil }
        let prompt = promptController(context: context, text: s.text("Filter (regular expression). Leave empty to delete.", "Фильтр (регулярное выражение). Пустое поле — удалить."), value: current ?? "", placeholder: s.text("e.g. casino|crypto", "например: казино|крипта"), characterLimit: 500, apply: { value in
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index, index < patterns.count {
                if trimmed.isEmpty {
                    patterns.remove(at: index)
                } else {
                    patterns[index] = trimmed
                }
            } else if !trimmed.isEmpty {
                patterns.append(trimmed)
            }
            MetaGramSettings.setList(.messageFilters, patterns)
            refresh()
        })
        presentImpl?(prompt)
    }

    let arguments = MetaGramListArguments(add: {
        edit(nil)
    }, open: { index in
        edit(index)
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, revision.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())
        let s = MetaGramStrings(presentationData.strings)

        var entries: [MetaGramListEntry] = [.add(id: 0, title: s.text("Add Filter", "Добавить фильтр"))]
        for (index, pattern) in MetaGramSettings.list(.messageFilters).enumerated() {
            entries.append(.item(id: Int32(index + 1), index: index, title: pattern, label: ""))
        }
        entries.append(.footer(id: 100000, text: s.text("Messages whose text matches a filter are hidden (case-insensitive). Tap a filter to change or delete it.", "Сообщения, текст которых подходит под фильтр, скрываются (регистр не важен). Нажмите на фильтр, чтобы изменить или удалить его.")))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(s.text("Message Filters", "Фильтры сообщений")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - Shadow ban list

private func metaGramShadowBanController(context: AccountContext, updated: @escaping () -> Void) -> ViewController {
    let revision = ValuePromise<Int32>(0, ignoreRepeated: false)
    let currentRevision = Atomic<Int32>(value: 0)
    let refresh: () -> Void = {
        revision.set(currentRevision.modify { $0 + 1 })
        updated()
    }

    let arguments = MetaGramListArguments(add: {
    }, open: { index in
        var ids = MetaGramSettings.list(.shadowBanned)
        if index < ids.count {
            ids.remove(at: index)
            MetaGramSettings.setList(.shadowBanned, ids)
            refresh()
        }
    })

    let peers: Signal<[EnginePeer.Id: EnginePeer?], NoError> = revision.get()
    |> mapToSignal { _ -> Signal<[EnginePeer.Id: EnginePeer?], NoError> in
        let peerIds: [EnginePeer.Id] = MetaGramSettings.list(.shadowBanned).compactMap { value -> EnginePeer.Id? in
            guard let rawId = Int64(value) else {
                return nil
            }
            return EnginePeer.Id(rawId)
        }
        return context.engine.data.get(EngineDataMap(
            peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))
        ))
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, peers)
    |> map { presentationData, peers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var presentationData = presentationData
        presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())
        let s = MetaGramStrings(presentationData.strings)

        var entries: [MetaGramListEntry] = []
        for (index, idString) in MetaGramSettings.list(.shadowBanned).enumerated() {
            var title = idString
            if let rawId = Int64(idString), let peer = peers[EnginePeer.Id(rawId)], let peer {
                title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            }
            entries.append(.item(id: Int32(index + 1), index: index, title: title, label: s.text("Remove", "Убрать")))
        }
        entries.append(.footer(id: 100000, text: s.text("Messages from these users are hidden. Add a user from their message menu; tap a user here to remove them.", "Сообщения этих пользователей скрываются. Добавить пользователя можно в меню его сообщения, убрать — нажатием здесь.")))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(s.text("Shadow Ban", "Теневой бан")), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
