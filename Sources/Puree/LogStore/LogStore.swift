import Foundation

public protocol LogStore {
    func prepare() throws
    func retrieveLogs(of group: String, completion: (Set<LogEntry>) -> Void)
    func add(_ log: LogEntry, for group: String, completion: (() -> Void)?)
    func add(_ logs: Set<LogEntry>, for group: String, completion: (() -> Void)?)
    func remove(_ log: LogEntry, from group: String, completion: (() -> Void)?)
    func remove(_ logs: Set<LogEntry>, from group: String, completion: (() -> Void)?)
    func flush()
}

public extension LogStore {
    func add(_ log: LogEntry, for group: String, completion: (() -> Void)?) {
        add([log], for: group, completion: completion)
    }

    func remove(_ log: LogEntry, from group: String, completion: (() -> Void)?) {
        remove([log], from: group, completion: completion)
    }
}
