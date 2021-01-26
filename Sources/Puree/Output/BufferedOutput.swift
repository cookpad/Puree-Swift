import Foundation

open class BufferedOutput: InstantiatableOutput {
    private let dateProvider: DateProvider = DefaultDateProvider()
    internal let readWriteQueue = DispatchQueue(label: "com.cookpad.Puree.Logger.BufferedOutput", qos: .background)

    required public init(logStore: LogStore, tagPattern: TagPattern, options: OutputOptions? = nil) {
        self.logStore = logStore
        self.tagPattern = tagPattern
    }

    public struct Chunk: Hashable {
        public let logs: Set<LogEntry>
        private(set) var retryCount: Int = 0

        fileprivate init(logs: Set<LogEntry>) {
            self.logs = logs
        }

        fileprivate mutating func incrementRetryCount() {
            retryCount += 1
        }

        public static func == (lhs: Chunk, rhs: Chunk) -> Bool {
            return lhs.logs == rhs.logs
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(logs)
        }
    }
    public struct Configuration {
        public var logEntryCountLimit: Int
        public var flushInterval: TimeInterval
        public var retryLimit: Int
        public var logDataSizeLimit: Int?

        public static let `default` = Configuration(logEntryCountLimit: 5, flushInterval: 10, retryLimit: 3, logDataSizeLimit: nil)
    }

    public let tagPattern: TagPattern
    private let logStore: LogStore
    public var configuration: Configuration = .default

    private var buffer: Set<LogEntry> = []
    private var currentWritingChunks: Set<Chunk> = []
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

    private var sizeLimit: Int? {
        return configuration.logDataSizeLimit
    }

    private var currentDate: Date {
        return dateProvider.now
    }

    deinit {
        timer?.invalidate()
    }

    public func start() {
        reloadLogStore()
        readWriteQueue.sync {
            flush()
        }
        setUpTimer()
    }

    public func resume() {
        reloadLogStore()
        readWriteQueue.sync {
            flush()
        }
        setUpTimer()
    }

    public func suspend() {
        timer?.invalidate()
    }

    public func emit(log: LogEntry) {
        readWriteQueue.sync {
            buffer.insert(log)
            logStore.add(log, for: storageGroup, completion: nil)

            if buffer.count >= logLimit {
                flush()
            } else if let logSizeLimit = configuration.logDataSizeLimit {
                let currentBufferedLogSize = buffer.reduce(0, { (size, log) -> Int in
                    size + (log.userData?.count ?? 0)
                })

                print("[hoge] count: \(buffer.count)")
                print("[hoge] count: \(currentBufferedLogSize)")

                if currentBufferedLogSize >= logSizeLimit {
                    flush()
                }
            }
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
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func tick(_ timer: Timer) {
        if let lastFlushDate = lastFlushDate {
            if currentDate.timeIntervalSince(lastFlushDate) > flushInterval {
                readWriteQueue.async {
                    self.flush()
                }
            }
        } else {
            readWriteQueue.async {
                self.flush()
            }
        }
    }

    private func reloadLogStore() {
        readWriteQueue.sync {
            buffer.removeAll()
            let semaphore = DispatchSemaphore(value: 0)
            logStore.retrieveLogs(of: storageGroup) { logs in
                let filteredLogs = logs.filter { log in
                    return !currentWritingChunks.contains { chunk in
                        return chunk.logs.contains(log)
                    }
                }
                buffer = buffer.union(filteredLogs)
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    private func flush() {
        dispatchPrecondition(condition: .onQueue(readWriteQueue))

        lastFlushDate = currentDate

        if buffer.isEmpty {
            return
        }

        let logCount = min(buffer.count, logLimit)
        let newBuffer = Set(buffer.dropFirst(logCount))
        let dropped = buffer.subtracting(newBuffer)
        buffer = newBuffer
        let logsToSend: Set<LogEntry>
        if let logDataSizeLimit = configuration.logDataSizeLimit {
            var logsUnderSizeLimit = Set<LogEntry>()

            var currentTotalLogSize = 0
            for log in dropped {
                if currentTotalLogSize + (log.userData?.count ?? 0) < logDataSizeLimit {
                    logsUnderSizeLimit.insert(log)
                    currentTotalLogSize += log.userData?.count ?? 0
                } else {
                    buffer = dropped.subtracting(logsUnderSizeLimit)
                    break
                }
            }
            logsToSend = logsUnderSizeLimit
        } else {
            logsToSend = dropped
        }
        callWriteChunk(Chunk(logs: logsToSend))
    }

    open func delay(try count: Int) -> TimeInterval {
        return 2.0 * pow(2.0, Double(count - 1))
    }

    private func callWriteChunk(_ chunk: Chunk) {
        dispatchPrecondition(condition: .onQueue(readWriteQueue))

        currentWritingChunks.insert(chunk)
        write(chunk) { success in
            if success {
                self.readWriteQueue.async {
                    self.currentWritingChunks.remove(chunk)
                    self.logStore.remove(chunk.logs, from: self.storageGroup, completion: nil)
                }
                return
            }

            var chunk = chunk
            chunk.incrementRetryCount()

            if chunk.retryCount <= self.retryLimit {
                let delay: TimeInterval = self.delay(try: chunk.retryCount)
                self.readWriteQueue.asyncAfter(deadline: .now() + delay) {
                    self.callWriteChunk(chunk)
                }
            }
        }
    }
}
