import Foundation

public typealias FilterOptions = [String: Any]

public protocol FilterSettingProtocol {
    init<F: Filter>(_ filter: F.Type, tagPattern: TagPattern, options: FilterOptions?)
    var makeFilter: () throws -> Filter { get }
}

public struct FilterSetting: FilterSettingProtocol {
    public init<F: Filter>(_ filter: F.Type, tagPattern: TagPattern, options: FilterOptions? = nil) {
        makeFilter = {
            return F(tagPattern: tagPattern, options: options)
        }
    }
    public let makeFilter: () throws -> Filter
}

public protocol Filter {
    var tagPattern: TagPattern { get }

    func convertToLogs(_ payload: [String: Any]?, tag: String, captured: String?, logger: Logger) -> Set<LogEntry>

    init(tagPattern: TagPattern, options: FilterOptions?)
}
