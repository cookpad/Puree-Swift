import Foundation

open class BufferedOutput: Output {
    private let dateProvider: DateProvider = DefaultDateProvider()
    public required init(logStore: LogStore, tagPattern: TagPattern, options: OutputOptions?) {
        self.logStore = logStore
        self.tagPattern = tagPattern
        self.options = options
    }

    public struct Chunk {
        public let logs: Set<LogEntry>
        private(set) var retryCount: Int = 0

        fileprivate init(logs: Set<LogEntry>) {
            self.logs = logs
        }

        fileprivate mutating func incrementRetryCount() {
            retryCount += 1
        }
    }
    public struct Configuration {
        public var logEntryCountLimit: Int
        public var flushInterval: TimeInterval
        public var retryLimit: Int

        public static let `default` = Configuration(logEntryCountLimit: 5, flushInterval: 10, retryLimit: 3)
    }

    public let tagPattern: TagPattern
    public let options: OutputOptions?
    private let logStore: LogStore
    public var configuration: Configuration = .default

    private var buffer: Set<LogEntry> = []
    private var timer: Timer?
    private var lastFlushDate: Date?
    private var logLimit: Int {
        return configuration.logEntryCountLimit
    }
    private var flushInterval: TimeInterval {
        return configuration.flushInterval
    }

    private var retryLimit: Int {
        return configuration.retryLimit
    }

    private var currentDate: Date {
        return dateProvider.now
    }

    deinit {
        timer?.invalidate()
    }

    public func start() {
        reloadLogStore()
        flush()

        setUpTimer()
    }

    public func resume() {
        reloadLogStore()
        flush()

        setUpTimer()
    }

    public func suspend() {
        timer?.invalidate()
    }

    public func emit(log: LogEntry) {
        buffer.insert(log)

        logStore.add(log, for: storageGroup, completion: nil)

        if buffer.count >= logLimit {
            flush()
        }
    }

    open func write(_ chunk: Chunk, completion: @escaping (Bool) -> Void) {
        completion(false)
    }

    open var storageGroup: String {
        let typeName = String(describing: type(of: self))
        return "\(tagPattern.pattern)_\(typeName)"
    }

    private func setUpTimer() {
        self.timer?.invalidate()

        let timer = Timer(timeInterval: 1.0,
                          target: self,
                          selector: #selector(tick(_:)),
                          userInfo: nil,
                          repeats: true)
        RunLoop.current.add(timer, forMode: .commonModes)
        self.timer = timer
    }

    @objc private func tick(_ timer: Timer) {
        if let lastFlushDate = lastFlushDate {
            if currentDate.timeIntervalSince(lastFlushDate) > flushInterval {
                flush()
            }
        } else {
            flush()
        }
    }

    private func reloadLogStore() {
        buffer.removeAll()

        logStore.retrieveLogs(of: storageGroup) { logs in
            buffer = buffer.union(logs)
        }
    }

    private func flush() {
        lastFlushDate = currentDate

        if buffer.isEmpty {
            return
        }

        let logCount = min(buffer.count, logLimit)
        let newBuffer = Set(buffer.dropFirst(logCount))
        let dropped = buffer.subtracting(newBuffer)
        buffer = newBuffer
        let chunk = Chunk(logs: dropped)
        callWriteChunk(chunk)
    }

    open func delay(try count: Int) -> TimeInterval {
        return 2.0 * pow(2.0, Double(count - 1))
    }

    private func callWriteChunk(_ chunk: Chunk) {
        write(chunk) { success in
            if success {
                self.logStore.remove(chunk.logs, from: self.storageGroup, completion: nil)
                return
            }

            var chunk = chunk
            chunk.incrementRetryCount()

            if chunk.retryCount <= self.retryLimit {
                let delay: TimeInterval = self.delay(try: chunk.retryCount)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.callWriteChunk(chunk)
                }
            }
        }
    }
}
