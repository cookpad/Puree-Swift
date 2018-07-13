import Foundation
import XCTest
import Puree

class TestingBufferedOutput: BufferedOutput {
    var shouldSuccess: Bool = true
    fileprivate(set) var calledWriteCount: Int = 0
    var writeCallback: (() -> Void)?

    override func write(_ chunk: BufferedOutput.Chunk, completion: @escaping (Bool) -> Void) {
        completion(shouldSuccess)
        calledWriteCount += 1
        writeCallback?()
    }

    override func delay(try count: Int) -> TimeInterval {
        return 0.2
    }
}

class BufferedOutputTests: XCTestCase {
    var output: TestingBufferedOutput!
    var logStore: InMemoryLogStore!

    override func setUp() {
        logStore = InMemoryLogStore()
        output = TestingBufferedOutput(logStore: logStore, tagPattern: TagPattern(string: "pv")!, options: nil)
        output.configuration.flushInterval = CFTimeInterval.infinity
        output.start()
    }

    func makeLog() -> LogEntry {
        return LogEntry(tag: "foo", date: Date())
    }

    func testBufferedOutput() {
        output.configuration.logEntryCountLimit = 1
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)
        output.emit(log: makeLog())
        XCTAssertEqual(output.calledWriteCount, 1)
    }

    func testBufferedOutputWithAlreadyStoredLogs() {
        output.configuration.logEntryCountLimit = 10
        output.configuration.flushInterval = 1

        let storedLogs: Set<LogEntry> = Set((0..<10).map { _ in LogEntry(tag: "pv", date: Date()) })
        logStore.add(storedLogs, for: "pv_TestingBufferedOutput", completion: nil)

        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)
        XCTAssertEqual(output.calledWriteCount, 0)

        output.resume()

        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 1)
    }

    func testBufferedOutputFlushedByInterval() {
        output.configuration.logEntryCountLimit = 10
        output.configuration.flushInterval = 1
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)
        output.emit(log: makeLog())
        XCTAssertEqual(output.calledWriteCount, 0)

        let expectation = self.expectation(description: "logs should be flushed")
        output.writeCallback = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testBufferedOutputNotFlushed() {
        output.configuration.logEntryCountLimit = 10
        output.configuration.flushInterval = 10
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)
        output.emit(log: makeLog())
        XCTAssertEqual(output.calledWriteCount, 0)

        output.writeCallback = {
            XCTFail("flush should not bbe called")
        }
        sleep(2)
    }

    func testHittingLogLimit() {
        output.configuration.logEntryCountLimit = 10
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)
        for i in 1..<10 {
            output.emit(log: makeLog())
            XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, i)
        }
        XCTAssertEqual(output.calledWriteCount, 0)

        output.emit(log: makeLog())
        XCTAssertEqual(output.calledWriteCount, 1)
        XCTAssertEqual(logStore.logs(for: "pv").count, 0)
    }

    func testRetryWhenFailed() {
        output.shouldSuccess = false
        output.configuration.logEntryCountLimit = 10
        output.configuration.retryLimit = 3
        XCTAssertEqual(output.calledWriteCount, 0)
        for _ in 0..<10 {
            output.emit(log: makeLog())
        }

        var expectation = self.expectation(description: "retry writeChunk")
        XCTAssertEqual(output.calledWriteCount, 1)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)
        output.writeCallback = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        expectation = self.expectation(description: "retry writeChunk")
        XCTAssertEqual(output.calledWriteCount, 2)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)
        output.writeCallback = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        expectation = self.expectation(description: "retry writeChunk")
        XCTAssertEqual(output.calledWriteCount, 3)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)
        output.writeCallback = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(output.calledWriteCount, 4)
    }

    func testParallelWrite() {
        output.configuration.logEntryCountLimit = 3
        output.configuration.retryLimit = 3

        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)

        let semaphore = DispatchSemaphore(value: 0)
        let testIndices = 0..<200

        for _ in testIndices {
            DispatchQueue.global(qos: .background).async {
                self.output.emit(log: self.makeLog())
                semaphore.signal()
            }
        }

        for _ in testIndices {
            semaphore.wait()
        }
        output.resume()

        let expectedWriteCount = Int(ceil(Double(testIndices.count) / Double(output.configuration.logEntryCountLimit)))
        XCTAssertEqual(output.calledWriteCount, expectedWriteCount)
    }

    override func tearDown() {
        super.tearDown()

        output.suspend()
        logStore.flush()
    }
}
