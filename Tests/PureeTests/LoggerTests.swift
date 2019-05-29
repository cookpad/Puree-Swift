import Foundation
import XCTest
import Puree

let buffer = TestingBuffer()

struct PVLogFilter: Filter {
    init(tagPattern: TagPattern, options: [String: Any]? = nil) {
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
    let tagPattern: TagPattern

    init(logStore: LogStore, tagPattern: TagPattern, options: [String: Any]? = nil) {
        self.tagPattern = tagPattern
    }

    func emit(log: LogEntry) {
        buffer.write(log, for: tagPattern.pattern)
    }
}

class LoggerTests: XCTestCase {
    let logStore = InMemoryLogStore()

    func testLoggerWithSingleTag() {
        let configuration = Logger.Configuration(logStore: logStore,
                                                 dateProvider: DefaultDateProvider(),
                                                 filterSettings: [
                                                    FilterSetting {
                                                        PVLogFilter(tagPattern: TagPattern(string: "pv")!)
                                                    },
            ],
                                                 outputSettings: [
                                                    OutputSetting {
                                                        PVLogOutput(logStore: $0, tagPattern: TagPattern(string: "pv")!)
                                                    },
            ])
        let logger = try! Logger(configuration: configuration)
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv")
        logger.suspend()

        XCTAssertEqual(buffer.logs(for: "pv").count, 1)

        let log = buffer.logs(for: "pv").first!
        guard let userInfo = try? JSONSerialization.jsonObject(with: log.userData!, options: []) as! [String: Any] else {
            return XCTFail("userInfo could not decoded")
        }
        XCTAssertEqual(userInfo["page_name"] as! String, "Top")
        XCTAssertEqual(userInfo["user_id"] as! Int, 100)
    }

    func testLoggerWithMultipleTag() {
        let configuration = Logger.Configuration(logStore: logStore,
                                                 dateProvider: DefaultDateProvider(),
                                                 filterSettings: [
                                                    FilterSetting {
                                                        PVLogFilter(tagPattern: TagPattern(string: "pv")!)
                                                    },
                                                    FilterSetting {
                                                        PVLogFilter(tagPattern: TagPattern(string: "pv2")!)
                                                    },
                                                    FilterSetting {
                                                        PVLogFilter(tagPattern: TagPattern(string: "pv.*")!)
                                                    },
            ],
                                                 outputSettings: [
                                                    OutputSetting {
                                                        PVLogOutput(logStore: $0, tagPattern: TagPattern(string: "pv")!)
                                                    },
                                                    OutputSetting {
                                                        PVLogOutput(logStore: $0, tagPattern: TagPattern(string: "pv2")!)
                                                    },
                                                    OutputSetting {
                                                        PVLogOutput(logStore: $0, tagPattern: TagPattern(string: "pv.*")!)
                                                    },
            ])
        let logger = try! Logger(configuration: configuration)
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv.top")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")
        logger.suspend()

        XCTAssertEqual(buffer.logs(for: "pv").count, 0)
        XCTAssertEqual(buffer.logs(for: "pv2").count, 2)
        XCTAssertEqual(buffer.logs(for: "pv.*").count, 1)
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
                                                    FilterSetting {
                                                        PVLogFilter(tagPattern: TagPattern(string: "pv")!)
                                                    },
                                                    CustomFilterSetting(tableName: "pv_log"),
                                                    FilterSetting {
                                                        PVLogFilter(tagPattern: TagPattern(string: "pv.*")!)
                                                    },
            ],
                                                 outputSettings: [
                                                    OutputSetting {
                                                        PVLogOutput(logStore: $0, tagPattern: TagPattern(string: "pv")!)
                                                    },
                                                    CustomOutputSetting(tableName: "pv_log"),
                                                    OutputSetting {
                                                        PVLogOutput(logStore: $0, tagPattern: TagPattern(string: "pv.*")!)
                                                    },
            ])
        let logger = try! Logger(configuration: configuration)
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv.top")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")
        logger.suspend()

        XCTAssertEqual(buffer.logs(for: "pv").count, 0)
        XCTAssertEqual(buffer.logs(for: "pv2").count, 2)
        XCTAssertEqual(buffer.logs(for: "pv.*").count, 1)
    }

    func testLoggerWithMultiThread() {
        let configuration = Logger.Configuration(logStore: logStore,
                                                 dateProvider: DefaultDateProvider(),
                                                 filterSettings: [
                                                    FilterSetting {
                                                        PVLogFilter(tagPattern: TagPattern(string: "pv")!)
                                                    },
            ],
                                                 outputSettings: [
                                                    OutputSetting {
                                                        PVLogOutput(logStore: $0, tagPattern: TagPattern(string: "pv")!)
                                                    },
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

        let logs = buffer.logs(for: "pv")
        XCTAssertEqual(logs.count, 100)

        for index in testIndices {
            let found = logs.contains { log -> Bool in
                guard let userInfo = try? JSONSerialization.jsonObject(with: log.userData!, options: []) as! [String: Any] else {
                    XCTFail("userInfo could not decoded")
                    return false
                }

                return (userInfo["index"] as! Int) == index
            }
            XCTAssertTrue(found)
        }
    }

    override func tearDown() {
        super.tearDown()

        buffer.flush()
        logStore.flush()
    }
}
