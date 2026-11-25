import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI

// MARK: - MetaGram Logs (a chat's deletions, edits and profile changes)

private final class MetaGramEventLogArguments {
    let copy: (String) -> Void
    let clear: () -> Void

    init(copy: @escaping (String) -> Void, clear: @escaping () -> Void) {
        self.copy = copy
        self.clear = clear
    }
}

private enum MetaGramEventLogEntry: ItemListNodeEntry {
    case event(id: Int32, label: String, text: String)
    case empty(id: Int32, text: String)
    case clear(id: Int32, title: String)
    case footer(id: Int32, text: String)

    var section: ItemListSectionId {
        switch self {
        case .event, .empty:
            return 0
        case .clear, .footer:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case let .event(id, _, _), let .empty(id, _), let .clear(id, _), let .footer(id, _):
            return id
        }
    }

    static func <(lhs: MetaGramEventLogEntry, rhs: MetaGramEventLogEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! MetaGramEventLogArguments
        switch self {
        case let .event(_, label, text):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil, longTapAction: {
                arguments.copy(text)
            })
        case let .empty(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .clear(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clear()
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func metaGramMediaKindTitle(_ kind: String, isRussian: Bool) -> String {
    switch kind {
    case "photo":
        return isRussian ? "Фото" : "Photo"
    case "video":
        return isRussian ? "Видео" : "Video"
    case "gif":
        return "GIF"
    case "voice":
        return isRussian ? "Голосовое сообщение" : "Voice message"
    case "round":
        return isRussian ? "Видеосообщение" : "Video message"
    case "sticker":
        return isRussian ? "Стикер" : "Sticker"
    default:
        return isRussian ? "Файл" : "File"
    }
}

private func metaGramEventLogEntries(events: [MetaGramLogEvent], authors: [EnginePeer.Id: EnginePeer?], presentationData: PresentationData) -> [MetaGramEventLogEntry] {
    let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yy HH:mm:ss"

    var entries: [MetaGramEventLogEntry] = []
    var nextId: Int32 = 0
    for event in events.reversed() {
        let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(event.date)))
        var authorPrefix = ""
        if let authorId = event.authorId, let author = authors[EnginePeer.Id(authorId)], let author {
            authorPrefix = author.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) + ": "
        }
        var mediaPrefix = ""
        if let mediaKind = event.mediaKind {
            mediaPrefix = "[\(metaGramMediaKindTitle(mediaKind, isRussian: isRussian))] "
        }

        let title: String
        let text: String
        switch event.kind {
        case .messageDeleted:
            title = isRussian ? "🗑 Удалил сообщение" : "🗑 Deleted a message"
            text = authorPrefix + mediaPrefix + (event.oldValue ?? "")
        case .messageEdited:
            title = isRussian ? "✏️ Изменил сообщение" : "✏️ Edited a message"
            let was = isRussian ? "Было" : "Before"
            let now = isRussian ? "Стало" : "After"
            text = authorPrefix + "\(was): \(event.oldValue ?? "—")\n\(now): \(event.newValue ?? "—")"
        case .nameChanged:
            title = isRussian ? "👤 Изменил имя" : "👤 Changed name"
            text = "\(event.oldValue ?? "—") → \(event.newValue ?? "—")"
        case .usernameChanged:
            title = isRussian ? "@ Изменил юзернейм" : "@ Changed username"
            let none = isRussian ? "нет" : "none"
            text = "\(event.oldValue.flatMap { "@" + $0 } ?? none) → \(event.newValue.flatMap { "@" + $0 } ?? none)"
        case .photoChanged:
            title = isRussian ? "🖼 Изменил аватар" : "🖼 Changed photo"
            switch event.newValue {
            case "set":
                text = isRussian ? "Поставил фото профиля" : "Set a profile photo"
            case "removed":
                text = isRussian ? "Удалил фото профиля" : "Removed the profile photo"
            default:
                text = isRussian ? "Сменил фото профиля" : "Changed the profile photo"
            }
        }
        entries.append(.event(id: nextId, label: "\(title) · \(date)", text: text.isEmpty ? "—" : text))
        nextId += 1
    }
    if events.isEmpty {
        entries.append(.empty(id: nextId, text: isRussian ? "Пока ничего. Здесь появятся удалённые и изменённые сообщения собеседника, смена имени, юзернейма и аватара — всё, что дойдёт до этого устройства, пока ведутся логи." : "Nothing yet. Messages the other side deletes or edits and their name, username and photo changes appear here, as they reach this device while logging is on."))
        nextId += 1
    } else {
        entries.append(.clear(id: 100000, title: isRussian ? "Очистить логи" : "Clear Logs"))
        entries.append(.footer(id: 100001, text: isRussian ? "Логи хранятся только на этом устройстве. Удержите запись, чтобы скопировать её текст." : "Logs are kept on this device only. Long-press an entry to copy its text."))
    }
    return entries
}

public func metaGramEventLogController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let revision = ValuePromise<Int32>(0, ignoreRepeated: false)
    let currentRevision = Atomic<Int32>(value: 0)
    var presentImpl: ((ViewController) -> Void)?

    let arguments = MetaGramEventLogArguments(copy: { text in
        UIPasteboard.general.string = text
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        presentImpl?(UndoOverlayController(presentationData: presentationData, content: .copy(text: isRussian ? "Скопировано" : "Copied"), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
    }, clear: {
        context.engine.messages.clearMetaGramEventLog(peerId: peerId)
        revision.set(currentRevision.modify { $0 + 1 })
    })

    let data: Signal<([MetaGramLogEvent], [EnginePeer.Id: EnginePeer?]), NoError> = revision.get()
    |> mapToSignal { _ -> Signal<([MetaGramLogEvent], [EnginePeer.Id: EnginePeer?]), NoError> in
        let events = context.engine.messages.metaGramEventLog(peerId: peerId)
        let authorIds = Array(Set(events.compactMap { $0.authorId.map { EnginePeer.Id($0) } }))
        return context.engine.data.get(EngineDataMap(
            authorIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))
        ))
        |> map { authors in
            return (events, authors)
        }
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, data)
    |> map { presentationData, data -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (events, authors) = data
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isRussian ? "Логи MetaGram" : "MetaGram Logs"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: metaGramEventLogEntries(events: events, authors: authors, presentationData: presentationData), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .current)
    }
    return controller
}
