import Foundation

public protocol FilterSettingProtocol {
    func makeFilter() throws -> Filter
}

public struct FilterSetting: FilterSettingProtocol {

    public init(makeFiilter: @escaping () -> Filter) {
        self.makeFilterBlock = makeFiilter
    }

    public init<F: InstantiatableFilter>(_ filter: F.Type, tagPattern: TagPattern) {
        makeFilterBlock = {
            return F(tagPattern: tagPattern)
        }
    }

    @available(*, unavailable, message: "Please conform InstantiatableFilter or use init with closure.")
    public init<F: Filter>(_ filter: F.Type, tagPattern: TagPattern, options: [String: Any]? = nil) {
        fatalError("unavailable")
    }

    public func makeFilter() throws -> Filter {
        return makeFilterBlock()
    }

    private let makeFilterBlock: () -> Filter
}

public protocol Filter {
    var tagPattern: TagPattern { get }

    func convertToLogs(_ payload: [String: Any]?, tag: String, captured: String?, logger: Logger) -> Set<LogEntry>
}

public protocol InstantiatableFilter: Filter {
    init(tagPattern: TagPattern)
}
