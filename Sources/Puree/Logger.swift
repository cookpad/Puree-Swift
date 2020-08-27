import Foundation

public final class Logger {
    public struct Configuration {
        public var logStoreType: LogStore.Type
        public var dateProvider: DateProvider = DefaultDateProvider()
        public var filterSettings: [FilterSettingProtocol] = []
        public var outputSettings: [OutputSettingProtocol] = []

        public init(logStoreType: LogStore.Type,
                    dateProvider: DateProvider = DefaultDateProvider(),
                    filterSettings: [FilterSettingProtocol],
                    outputSettings: [OutputSettingProtocol]) {
            self.logStoreType = logStoreType
            self.dateProvider = dateProvider
            self.filterSettings = filterSettings
            self.outputSettings = outputSettings
        }
    }

    private let configuration: Configuration
    private let dispatchQueue = DispatchQueue(label: "com.cookpad.Puree.Logger", qos: .background)
    private let logStore: LogStore
    private(set) var filters: [Filter] = []
    private(set) var outputs: [Output] = []

    public var currentDate: Date {
        return configuration.dateProvider.now
    }

    public init(configuration: Configuration) throws {
        self.configuration = configuration

        logStore = try configuration.logStoreType.init()
        try configureFilterPlugins()
        try configureOutputPlugins()

        start()
    }

    private func configureFilterPlugins() throws {
        filters = try configuration.filterSettings.map { try $0.makeFilter() }
    }

    private func configureOutputPlugins() throws {
        outputs = try configuration.outputSettings.map { try $0.makeOutput(logStore) }
    }

    public func postLog(_ payload: [String: Any]?, tag: String) {
        dispatchQueue.async {
            func matchesOutputs(with tag: String) -> [Output] {
                return self.outputs.filter { $0.tagPattern.match(in: tag) != nil }
            }

            for log in self.filteredLogs(with: payload, tag: tag) {
                for output in matchesOutputs(with: tag) {
                    output.emit(log: log)
                }
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

    private func start() {
        dispatchQueue.async {
            self.outputs.forEach { $0.start() }
        }
    }

    public func suspend() {
        dispatchQueue.sync {
            outputs.forEach { $0.suspend() }
        }
    }

    public func resume() {
        dispatchQueue.async {
            self.outputs.forEach { $0.resume() }
        }
    }

    public func shutdown() {
        dispatchQueue.sync {
            filters.removeAll()
            outputs.forEach { $0.suspend() }
            outputs.removeAll()
        }
    }
}
