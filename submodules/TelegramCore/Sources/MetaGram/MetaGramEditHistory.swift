import Foundation
import Postbox

/// One earlier version of an edited message (MetaGram "Save Edits History").
public struct MetaGramEditHistoryEntry: Codable, Equatable {
    /// When this version was current from: the message date, or the previous edit's date.
    public let date: Int32
    public let text: String

    public init(date: Int32, text: String) {
        self.date = date
        self.text = text
    }
}

/// Earlier versions of edited messages, kept apart from Postbox in one JSON file per account
/// (`<account media dir>/metagram-edit-history.json`): a history fill that stores a message again
/// rewrites it from the server, which would drop anything kept inside the message itself.
final class MetaGramEditHistoryStore {
    static let shared = MetaGramEditHistoryStore()

    private let lock = NSLock()
    private var loaded: [String: [String: [MetaGramEditHistoryEntry]]] = [:]

    private static let fileName = "metagram-edit-history.json"
    /// Bounds the file: older versions beyond this, per message, are dropped.
    private static let maxEntriesPerMessage = 50

    private static func key(_ id: MessageId) -> String {
        return "\(id.peerId.toInt64()):\(id.namespace):\(id.id)"
    }

    private static func path(_ basePath: String) -> String {
        return basePath + "/" + fileName
    }

    /// Requires `lock`.
    private func table(_ basePath: String) -> [String: [MetaGramEditHistoryEntry]] {
        if let table = self.loaded[basePath] {
            return table
        }
        var table: [String: [MetaGramEditHistoryEntry]] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: MetaGramEditHistoryStore.path(basePath))),
           let decoded = try? JSONDecoder().decode([String: [MetaGramEditHistoryEntry]].self, from: data) {
            table = decoded
        }
        self.loaded[basePath] = table
        return table
    }

    func entries(basePath: String, id: MessageId) -> [MetaGramEditHistoryEntry] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.table(basePath)[MetaGramEditHistoryStore.key(id)] ?? []
    }

    func append(basePath: String, id: MessageId, entry: MetaGramEditHistoryEntry) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var table = self.table(basePath)
        let key = MetaGramEditHistoryStore.key(id)
        var list = table[key] ?? []
        if list.last == entry {
            return
        }
        list.append(entry)
        if list.count > MetaGramEditHistoryStore.maxEntriesPerMessage {
            list.removeFirst(list.count - MetaGramEditHistoryStore.maxEntriesPerMessage)
        }
        table[key] = list
        self.loaded[basePath] = table
        // the table is a value: the write encodes this version, off the caller's queue
        MetaGramFileWriter.shared.schedule(path: MetaGramEditHistoryStore.path(basePath), makeData: {
            return try? JSONEncoder().encode(table)
        })
    }
}

enum MetaGramEditHistory {
    /// Called with a stored message about to be replaced by a server edit: keeps its text if it changed.
    static func recordEdit(mediaBox: MediaBox, previous: Message, newText: String) {
        MetaGramEventLog.recordEdit(basePath: mediaBox.basePath, previous: previous, newText: newText)
        guard MetaGramSettings.get(.saveEditsHistory), previous.id.namespace == Namespaces.Message.Cloud else {
            return
        }
        if previous.text == newText {
            return
        }
        var date = previous.timestamp
        for attribute in previous.attributes {
            if let attribute = attribute as? EditedMessageAttribute {
                date = attribute.date
            }
        }
        MetaGramEditHistoryStore.shared.append(basePath: mediaBox.basePath, id: previous.id, entry: MetaGramEditHistoryEntry(date: date, text: previous.text))
    }
}

public extension TelegramEngine.Messages {
    /// Earlier versions of the message, oldest first; empty if it was never edited (or not while saving was on).
    func metaGramEditHistory(messageId: EngineMessage.Id) -> [MetaGramEditHistoryEntry] {
        return MetaGramEditHistoryStore.shared.entries(basePath: self.account.postbox.mediaBox.basePath, id: messageId)
    }
}
