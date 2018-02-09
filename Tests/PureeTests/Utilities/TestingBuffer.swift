import Foundation
import Puree

class TestingBuffer {
    private var logs: [String: [LogEntry]] = [:]

    init() { }

    func logs(for key: String) -> [LogEntry] {
        return logs[key] ?? []
    }

    func write(_ log: LogEntry, for key: String) {
        if logs[key] == nil {
            logs[key] = []
        }
        logs[key]?.append(log)
    }

    func flush() {
        logs.removeAll()
    }
}
