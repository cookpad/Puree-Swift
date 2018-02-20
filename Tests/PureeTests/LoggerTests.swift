import Foundation
import XCTest
import Puree

let buffer = TestingBuffer()

struct PVLogFilter: Filter {
    init(tagPattern: TagPattern, options: FilterOptions?) {
        self.tagPattern = tagPattern
    }

    var tagPattern: TagPattern = TagPattern(string: "")!

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
        buffer.write(log, for: tagPattern.pattern)
    }
}

class LoggerTests: XCTestCase {
    let logStore = InMemoryLogStore()

    func testLoggerWithSingleTag() {
        let configuration = Logger.Configuration(logStore: logStore,
                                                 dateProvider: DefaultDateProvider(),
                                                 filterSettings: [
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv")!)
            ],
                                                 outputSettings: [
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv")!)
            ])
        let logger = try! Logger(configuration: configuration)
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv")

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
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv")!),
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv2")!),
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv.*")!)
            ],
                                                 outputSettings: [
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv")!),
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv2")!),
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv.*")!)
            ])
        let logger = try! Logger(configuration: configuration)
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv.top")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")

        XCTAssertEqual(buffer.logs(for: "pv").count, 0)
        XCTAssertEqual(buffer.logs(for: "pv2").count, 2)
        XCTAssertEqual(buffer.logs(for: "pv.*").count, 1)
    }

    func testLoggerWithCustomSetting() {
        struct CustomFilterSetting: FilterSettingProtocol {
            func makeFilter() throws -> Filter {
                return PVLogFilter(tagPattern: TagPattern(string: "pv2")!, options: [:])
            }
        }

        struct CustomOutputSetting: OutputSettingProtocol {
            func makeOutput(_ logStore: LogStore) throws -> Output {
                return PVLogOutput(logStore: logStore, tagPattern: TagPattern(string: "pv2")!, options: [:])
            }
        }

        let configuration = Logger.Configuration(logStore: logStore,
                                                 dateProvider: DefaultDateProvider(),
                                                 filterSettings: [
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv")!),
                                                    CustomFilterSetting(),
                                                    FilterSetting(PVLogFilter.self, tagPattern: TagPattern(string: "pv.*")!)
            ],
                                                 outputSettings: [
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv")!),
                                                    CustomOutputSetting(),
                                                    OutputSetting(PVLogOutput.self, tagPattern: TagPattern(string: "pv.*")!)
            ])
        let logger = try! Logger(configuration: configuration)
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv.top")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")
        logger.postLog(["page_name": "Top", "user_id": 100], tag: "pv2")

        XCTAssertEqual(buffer.logs(for: "pv").count, 0)
        XCTAssertEqual(buffer.logs(for: "pv2").count, 2)
        XCTAssertEqual(buffer.logs(for: "pv.*").count, 1)
    }

    override func tearDown() {
        super.tearDown()

        buffer.flush()
        logStore.flush()
    }
}
