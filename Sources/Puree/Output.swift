import Foundation

public typealias OutputOptions = [String: Any]

public protocol OutputSettingProtocol {
    func makeOutput(_ logStore: LogStore) throws -> Output
}

public struct OutputSetting: OutputSettingProtocol {
    public init<O: Output>(_ output: O.Type, tagPattern: TagPattern, options: OutputOptions? = nil) {
        makeOutputBlock = { logStore in
            return O(logStore: logStore, tagPattern: tagPattern, options: options)
        }
    }

    public func makeOutput(_ logStore: LogStore) -> Output {
        return makeOutputBlock(logStore)
    }

    private let makeOutputBlock: (_ logStore: LogStore) -> Output
}

public protocol Output {
    var tagPattern: TagPattern { get }
    var storageGroup: String { get }

    func start()
    func resume()
    func suspend()
    func emit(log: LogEntry)

    init(logStore: LogStore, tagPattern: TagPattern, options: OutputOptions?)
}

public extension Output {
    func start() {
    }

    func resume() {
    }

    func suspend() {
    }

    var storageGroup: String {
        let typeName = String(describing: type(of: self))
        return "\(tagPattern.pattern)_\(typeName)"
    }
}
