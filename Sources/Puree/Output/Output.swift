import Foundation

public protocol OutputSettingProtocol {
    func makeOutput(_ logStore: LogStore) throws -> Output
}

public struct OutputSetting: OutputSettingProtocol {

    public init(makeOutput: @escaping (_ logStore: LogStore) -> Output) {
        self.makeOutputBlock = makeOutput
    }

    public init<O: InstantiatableOutput>(_ output: O.Type, tagPattern: TagPattern, options: OutputOptions? = nil) {
        makeOutputBlock = { logStore in
            return O(logStore: logStore, tagPattern: tagPattern, options: options)
        }
    }

    @available(*, unavailable, message: "Please conform InstantiatableOutput or use init with closure.")
    public init<O: Output>(_ output: O.Type, tagPattern: TagPattern, options: OutputOptions? = nil) {
        fatalError("unavailable")
    }

    public func makeOutput(_ logStore: LogStore) -> Output {
        return makeOutputBlock(logStore)
    }

    private let makeOutputBlock: (_ logStore: LogStore) -> Output
}

public protocol Output {
    var tagPattern: TagPattern { get }

    func start()
    func resume()
    func suspend()
    func emit(log: LogEntry)

}

public typealias OutputOptions = [String: Any]

public protocol InstantiatableOutput: Output {
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
