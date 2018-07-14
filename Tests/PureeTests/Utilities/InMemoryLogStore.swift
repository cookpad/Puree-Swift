import Foundation
import Puree

class InMemoryLogStore: LogStore {
    private var buffer: [String: Set<LogEntry>] = [:]

    func prepare() throws {
    }

    func logs(for group: String) -> Set<LogEntry> {
        if let logs = buffer[group] {
            return logs
        }
        return []
    }

    func add(_ logs: Set<LogEntry>, for group: String, completion: (() -> Void)?) {
        if buffer[group] == nil {
            buffer[group] = Set<LogEntry>()
        }
        buffer[group]?.formUnion(logs)
        completion?()
    }

    func remove(_ logs: Set<LogEntry>, from group: String, completion: (() -> Void)?) {
        buffer[group]?.subtract(logs)
        completion?()
    }

    func retrieveLogs(of group: String, completion: (Set<LogEntry>) -> Void) {
        if let logs = buffer[group] {
            return completion(logs)
        }
        completion([])
    }

    func flush() {
        buffer.removeAll()
    }
}
