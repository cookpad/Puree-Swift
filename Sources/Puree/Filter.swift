import Foundation

public typealias FilterOptions = [String: Any]

public protocol FilterSettingProtocol {
    func makeFilter() throws -> Filter
}

public struct FilterSetting: FilterSettingProtocol {
    public init<F: Filter>(_ filter: F.Type, tagPattern: TagPattern, options: FilterOptions? = nil) {
        makeFilterBlock = {
            return F(tagPattern: tagPattern, options: options)
        }
    }

    public func makeFilter() throws -> Filter {
        return try makeFilterBlock()
    }

    private let makeFilterBlock: () throws -> Filter
}

public protocol Filter {
    var tagPattern: TagPattern { get }

    func convertToLogs(_ payload: [String: Any]?, tag: String, captured: String?, logger: Logger) -> Set<LogEntry>

    init(tagPattern: TagPattern, options: FilterOptions?)
}
