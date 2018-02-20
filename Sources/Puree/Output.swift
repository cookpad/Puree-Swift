import Foundation

public typealias OutputOptions = [String: Any]

public protocol OutputSettingProtocol {
    init<O: Output>(_ output: O.Type, tagPattern: TagPattern, options: OutputOptions?)
    var makeOutput: (_ logStore: LogStore) throws -> Output { get }
}

public struct OutputSetting: OutputSettingProtocol {
    public init<O: Output>(_ output: O.Type, tagPattern: TagPattern, options: OutputOptions? = nil) {
        makeOutput = { logStore in
            return O(logStore: logStore, tagPattern: tagPattern, options: options)
        }
    }
    public let makeOutput: (_ logStore: LogStore) throws -> Output
}

public protocol Output {
    var tagPattern: TagPattern { get }

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
}
