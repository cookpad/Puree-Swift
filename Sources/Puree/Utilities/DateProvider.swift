import Foundation

public protocol DateProvider {
    var now: Date { get }
}

public struct DefaultDateProvider: DateProvider {
    public init() { }
    public var now: Date {
        return Date()
    }
}
