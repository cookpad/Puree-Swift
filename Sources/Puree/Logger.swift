import Foundation

public final class Logger {
    public struct Configuration {
        public var logStore: LogStore
        public var dateProvider: DateProvider = DefaultDateProvider()
        public var filterSettings: [FilterSettingProtocol] = []
        public var outputSettings: [OutputSettingProtocol] = []

        public init(logStore: LogStore = FileLogStore.default,
                    dateProvider: DateProvider = DefaultDateProvider(),
                    filterSettings: [FilterSettingProtocol],
                    outputSettings: [OutputSettingProtocol]) {
            self.logStore = logStore
            self.dateProvider = dateProvider
            self.filterSettings = filterSettings
            self.outputSettings = outputSettings
        }
    }

    private let configuration: Configuration
    private(set) var filters: [Filter] = []
    private(set) var outputs: [Output] = []

    public var currentDate: Date {
        return configuration.dateProvider.now
    }

    var logStore: LogStore {
        return configuration.logStore
    }

    public init(configuration: Configuration) throws {
        self.configuration = configuration

        try configuration.logStore.prepare()
        try configureFilterPlugins()
        try configureOutputPlugins()

        outputs.forEach { $0.start() }
    }

    private func configureFilterPlugins() throws {
        filters = try configuration.filterSettings.map { try $0.makeFilter() }
    }

    private func configureOutputPlugins() throws {
        outputs = try configuration.outputSettings.map { try $0.makeOutput(logStore) }
    }

    public func postLog(_ payload: [String: Any]?, tag: String) {
        func matchesOutputs(with tag: String) -> [Output] {
            return outputs.filter { $0.tagPattern.match(in: tag) != nil }
        }

        for log in filteredLogs(with: payload, tag: tag) {
            for output in matchesOutputs(with: tag) {
                output.emit(log: log)
            }
        }
    }

    private func filteredLogs(with payload: [String: Any]?, tag: String) -> [LogEntry] {
        var logs: [LogEntry] = []
        for filter in filters {
            let match = filter.tagPattern.match(in: tag)
            if let match = match {
                let filteredLogs = filter.convertToLogs(payload, tag: tag, captured: match.captured, logger: self)
                logs.append(contentsOf: filteredLogs)
            } else {
                continue
            }
        }
        return logs
    }

    public func suspend() {
        outputs.forEach { $0.suspend() }
    }

    public func resume() {
        outputs.forEach { $0.resume() }
    }

    public func shutdown() {
        filters.removeAll()
        suspend()
        outputs.removeAll()
    }

    deinit {
        shutdown()
    }
}
