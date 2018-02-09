import Foundation
import XCTest
import Puree

class FileLogStoreTests: XCTestCase {
    var logStore: LogStore {
        return FileLogStore.default
    }

    override func setUp() {
        super.setUp()

        try! logStore.prepare()
        logStore.flush()
    }

    override func tearDown() {
        super.tearDown()
        logStore.flush()
    }

    func makeLog() -> LogEntry {
        return LogEntry(tag: "tag", date: Date())
    }

    func testAddAndRemoveLogs() {
        var callbackIsCalled = false
        let log = makeLog()
        logStore.add(log, for: "foo") {
            callbackIsCalled = true
        }

        XCTAssertTrue(callbackIsCalled)

        logStore.retrieveLogs(of: "foo") { logs in
            XCTAssertEqual(logs.count, 1)
        }
        logStore.retrieveLogs(of: "bar") { logs in
            XCTAssertTrue(logs.isEmpty)
        }

        let anotherLog = makeLog()
        logStore.add(anotherLog, for: "foo", completion: nil)

        logStore.remove(log, from: "bar") {
            self.logStore.retrieveLogs(of: "foo") { logs in
                XCTAssertEqual(logs.count, 2)
            }
        }
        logStore.remove(log, from: "foo") {
            self.logStore.retrieveLogs(of: "foo") { logs in
                XCTAssertEqual(logs.count, 1)
                XCTAssertEqual(logs.first!, anotherLog)
            }
        }
    }
}
