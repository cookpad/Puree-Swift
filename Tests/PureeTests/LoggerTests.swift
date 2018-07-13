import Foundation
import XCTest
import Puree

struct PVLogFilter: Filter {
    init(tagPattern: TagPattern, options: FilterOptions?) {
        self.tagPattern = tagPattern
    }

    let tagPattern: TagPattern

    func convertToLogs(_ payload: [String: Any]?, tag: String, captured: String?, logger: Logger) -> Set<LogEntry> {
        var log = LogEntry(tag: tag, date: logger.currentDate)
        guard let userInfo = payload, let userData = try? JSONSerialization.data(withJSONObject: userInfo, options: []) else {
            XCTFail("could not encode userInfo")
            return []
        }
        log.userData = userData
        return [log]
    }
}

struct PVLogOutput: Output {
    let logStore: LogStore
    let tagPattern: TagPattern

    init(logStore: LogStore, tagPattern: TagPattern, options: OutputOptions?) {
        self.logStore = logStore
        self.tagPattern = tagPattern
    }

    func emit(log: LogEntry) {
        logStore.add(log, for: tagPattern.pattern, completion: nil)
    }
}

class LoggerTests: XCTestCase {
    let logStore = InMemoryLogStore()

    func testLoggerWithSingleTag() {
        let configuration = Logger.Configuration(logStore: logStore,
                                                 dateProvider: DefaultDateProvider(),
                                                 filterSettings: [
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv")!),
            ],
                                                 outputSettings: [
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv")!),
            ])
        let logger = try! Logger(configuration: configuration)
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv")
        logger.suspend()

        logStore.retrieveLogs(of: "pv") { logs in
            XCTAssertEqual(logs.count, 1)

            let log = logs.first!
            guard let userInfo = try? JSONSerialization.jsonObject(with: log.userData!, options: []) as! [String: Any] else {
                return XCTFail("userInfo could not decoded")
            }
            XCTAssertEqual(userInfo["page_name"] as! String, "Top")
            XCTAssertEqual(userInfo["user_id"] as! Int, 100)
        }
    }

    func testLoggerWithMultipleTag() {
        let configuration = Logger.Configuration(logStore: logStore,
                                                 dateProvider: DefaultDateProvider(),
                                                 filterSettings: [
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv")!),
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv2")!),
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv.*")!),
            ],
                                                 outputSettings: [
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv")!),
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv2")!),
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv.*")!),
            ])
        let logger = try! Logger(configuration: configuration)
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv.top")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")
        logger.suspend()

        logStore.retrieveLogs(of: "pv") { logs in
            XCTAssertEqual(logs.count, 0)
        }
        logStore.retrieveLogs(of: "pv2") { logs in
            XCTAssertEqual(logs.count, 2)
        }
        logStore.retrieveLogs(of: "pv.*") { logs in
            XCTAssertEqual(logs.count, 1)
        }
    }

    func testLoggerWithCustomSetting() {
        struct CustomFilterSetting: FilterSettingProtocol {
            private let tableName: String

            init(tableName: String) {
                self.tableName = tableName
            }

            func makeFilter() throws -> Filter {
                return PVLogFilter(tagPattern: TagPattern(string: "pv2")!, options: ["table_name": tableName])
            }
        }

        struct CustomOutputSetting: OutputSettingProtocol {
            private let tableName: String

            init(tableName: String) {
                self.tableName = tableName
            }

            func makeOutput(_ logStore: LogStore) throws -> Output {
                return PVLogOutput(logStore: logStore, tagPattern: TagPattern(string: "pv2")!, options: ["table_name": tableName])
            }
        }

        let configuration = Logger.Configuration(logStore: logStore,
                                                 dateProvider: DefaultDateProvider(),
                                                 filterSettings: [
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv")!),
                                                    CustomFilterSetting(tableName: "pv_log"),
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv.*")!),
            ],
                                                 outputSettings: [
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv")!),
                                                    CustomOutputSetting(tableName: "pv_log"),
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv.*")!),
            ])
        let logger = try! Logger(configuration: configuration)
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv.top")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")
        logger.suspend()

        logStore.retrieveLogs(of: "pv") { logs in
            XCTAssertEqual(logs.count, 0)
        }
        logStore.retrieveLogs(of: "pv2") { logs in
            XCTAssertEqual(logs.count, 2)
        }
        logStore.retrieveLogs(of: "pv.*") { logs in
            XCTAssertEqual(logs.count, 1)
        }
    }

    func testLoggerWithMultiThread() {
        let configuration = Logger.Configuration(logStore: logStore,
                                                 dateProvider: DefaultDateProvider(),
                                                 filterSettings: [
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv")!),
                                                    ],
                                                 outputSettings: [
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv")!),
                                                    ])
        let logger = try! Logger(configuration: configuration)

        let semaphore = DispatchSemaphore(value: 0)
        let testIndices = 0..<100

        for index in testIndices {
            DispatchQueue.global(qos: .background).async {
                logger.postLog(["queue": "global", "index": index], tag: "pv")
                semaphore.signal()
            }
        }

        for _ in testIndices {
            semaphore.wait()
        }
        logger.suspend()
        logStore.retrieveLogs(of: "pv") { logs in
            XCTAssertEqual(logs.count, 100)

            for index in testIndices {
                let found = logs.contains(where: { log -> Bool in
                    guard let userInfo = try? JSONSerialization.jsonObject(with: log.userData!, options: []) as! [String: Any] else {
                        XCTFail("userInfo could not decoded")
                        return false
                    }

                    return (userInfo["index"] as! Int) == index
                })
                XCTAssertTrue(found)
            }
        }
    }

    override func tearDown() {
        super.tearDown()

        logStore.flush()
    }
}
