import Foundation

public struct LogEntry: Codable, Hashable {
    public var identifier: UUID = UUID()
    public var tag: String
    public var date: Date
    public var userData: Data?

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    public static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        return lhs.identifier == rhs.identifier
    }

    public init(tag: String, date: Date = Date(), userData: Data? = nil) {
        self.tag = tag
        self.date = date
        self.userData = userData
    }
}
