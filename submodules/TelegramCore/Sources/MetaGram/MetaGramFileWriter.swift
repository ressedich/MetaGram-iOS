import Foundation

/// Writes MetaGram's JSON files (edit history, logs) off the database queue, at most once per path every 1.5 s: a
/// burst of events (a chat cleared, many edits) becomes one write of the latest data instead of one per event.
final class MetaGramFileWriter {
    static let shared = MetaGramFileWriter()

    private let queue = DispatchQueue(label: "org.metagram.file-writer", qos: .utility)
    private let lock = NSLock()
    private var pending: [String: () -> Data?] = [:]

    /// Schedules writing `makeData()` to `path`; a later call for the same path before the write replaces it.
    func schedule(path: String, makeData: @escaping () -> Data?) {
        self.lock.lock()
        let alreadyScheduled = self.pending[path] != nil
        self.pending[path] = makeData
        self.lock.unlock()
        if alreadyScheduled {
            return
        }
        self.queue.asyncAfter(deadline: .now() + 1.5, execute: { [weak self] in
            guard let self else {
                return
            }
            self.lock.lock()
            let makeData = self.pending.removeValue(forKey: path)
            self.lock.unlock()
            if let data = makeData?() {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        })
    }
}
