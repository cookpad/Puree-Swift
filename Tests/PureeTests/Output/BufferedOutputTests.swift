import Foundation
import XCTest
@testable import Puree

private func makeLog() -> LogEntry {
    return LogEntry(tag: "foo", date: Date())
}

class TestingBufferedOutput: BufferedOutput {
    var shouldSuccess: Bool = true
    fileprivate(set) var calledWriteCount: Int = 0
    var writeCallback: (() -> Void)?
    var waitUntilCurrentCompletionBlock: (() -> Void)?

    override func write(_ chunk: BufferedOutput.Chunk, completion: @escaping (Bool) -> Void) {
        calledWriteCount += 1
        completion(shouldSuccess)
        writeCallback?()
    }

    override func delay(try count: Int) -> TimeInterval {
        return 0.2
    }

    func waitUntilCurrentQueuedJobFinished() {
        waitUntilCurrentCompletionBlock?()
        readWriteQueue.sync {
        }
    }
}

class BufferedOutputTests: XCTestCase {
    var output: TestingBufferedOutput!
    let logStore = InMemoryLogStore()

    override func setUp() {
        output = TestingBufferedOutput(logStore: logStore, tagPattern: TagPattern(string: "pv")!)
        output.configuration.flushInterval = TimeInterval.infinity
        output.start()
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

        let storedLogs: Set<LogEntry> = Set((0..<10).map { _ in makeLog() })
        logStore.add(storedLogs, for: "pv_TestingBufferedOutput", completion: nil)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)
        XCTAssertEqual(output.calledWriteCount, 0)

        output.resume()
        output.waitUntilCurrentQueuedJobFinished()

        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 1)
    }

    func testBufferedOutputSendBufferedLogs() {
        output.configuration.logEntryCountLimit = 10

        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)

        output.emit(log: makeLog())
        output.sendBufferedLogs()
        output.waitUntilCurrentQueuedJobFinished()

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
        wait(for: [expectation], timeout: 10.0)
    }

    func testBufferedOutputNotFlushed() {
        output.configuration.logEntryCountLimit = 10
        output.configuration.flushInterval = 10
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)
        output.emit(log: makeLog())
        XCTAssertEqual(output.calledWriteCount, 0)

        output.writeCallback = {
            XCTFail("writeBufferedLogs should not be called")
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

    func testHittingLogSizeLimit() {
        // Set maximum chunk size as 15bytes
        output.configuration.chunkDataSizeLimit = 15

        // Disable to send according to log count
        output.configuration.logEntryCountLimit = .max

        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)

        // Emit one log entry whose size is 10bytes.
        // This should not be sent at this time because size limit has not exceeded yet.
        var log1 = makeLog()
        log1.userData = "0123456789".data(using: .utf8)
        output.emit(log: log1)
        XCTAssertEqual(output.calledWriteCount, 0)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 1)

        // Emit one more log entry whose size is 10bytes.
        // Now `log1` should be sent and `log2` shoud not because reaching to size limit. `log2` should remain in the `logStore` .
        var log2 = makeLog()
        log2.userData = "0123456789".data(using: .utf8)
        output.emit(log: log2)
        output.waitUntilCurrentQueuedJobFinished()
        XCTAssertEqual(output.calledWriteCount, 1)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 1)

        // Emit one more log entry whose size is 3bytes.
        // Now `log2` and `log3` should not be sent yet because total size has not reached the limit.
        var log3 = makeLog()
        log3.userData = "012".data(using: .utf8)
        output.emit(log: log3)
        output.waitUntilCurrentQueuedJobFinished()
        XCTAssertEqual(output.calledWriteCount, 1)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 2)
    }

    func testEmittingOneLogLargerThanSizeLimit() {
        // Set maximum chunk size as 5bytes
        output.configuration.chunkDataSizeLimit = 5

        // Disable to send according to log count
        output.configuration.logEntryCountLimit = .max

        // A log entry that has data larger than limit will be discarded.
        var log1 = makeLog()
        log1.userData = "0123456789".data(using: .utf8)
        output.emit(log: log1)
        XCTAssertEqual(output.calledWriteCount, 0)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
    }

    func testRetryWhenFailed() {
        output.shouldSuccess = false
        output.configuration.logEntryCountLimit = 10
        output.configuration.retryLimit = 3
        XCTAssertEqual(output.calledWriteCount, 0)
        for _ in 0..<10 {
            output.emit(log: makeLog())
        }
        output.waitUntilCurrentQueuedJobFinished()

        var expectation = self.expectation(description: "retry writeChunk")
        XCTAssertEqual(output.calledWriteCount, 1)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)
        output.writeCallback = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        expectation = self.expectation(description: "retry writeChunk")
        XCTAssertEqual(output.calledWriteCount, 2)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)
        output.writeCallback = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        expectation = self.expectation(description: "retry writeChunk")
        XCTAssertEqual(output.calledWriteCount, 3)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)
        output.writeCallback = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(output.calledWriteCount, 4)
    }

    func testParallelWrite() {
        output.configuration.logEntryCountLimit = 2
        output.configuration.retryLimit = 3
        let testIndices = 0..<1000
        let expectedWriteCount = 500

        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)

        var writeCallbackCalledCount = 0
        output.writeCallback = {
            writeCallbackCalledCount += 1
        }

        let semaphore = DispatchSemaphore(value: 0)
        for _ in testIndices {
            DispatchQueue.global(qos: .background).async {
                self.output.emit(log: makeLog())
                semaphore.signal()
            }
        }

        for _ in testIndices {
            semaphore.wait()
        }
        output.resume()

        XCTAssertEqual(output.calledWriteCount, expectedWriteCount)
        XCTAssertEqual(writeCallbackCalledCount, expectedWriteCount)
    }

    override func tearDown() {
        super.tearDown()

        output.suspend()
        logStore.flush()
    }
}

class TestingBufferedOutputAsync: TestingBufferedOutput {
    override var storageGroup: String {
        return "pv_TestingBufferedOutput"
    }

    override func write(_ chunk: BufferedOutput.Chunk, completion: @escaping (Bool) -> Void) {
        calledWriteCount += 1
        DispatchQueue.global().async {
            Thread.sleep(forTimeInterval: 0.1)
            completion(self.shouldSuccess)
            self.writeCallback?()
        }
    }
}

class BufferedOutputAsyncTests: XCTestCase {
    var output: TestingBufferedOutputAsync!
    let logStore = InMemoryLogStore()

    override func setUp() {
        output = TestingBufferedOutputAsync(logStore: logStore, tagPattern: TagPattern(string: "pv")!)
        output.configuration.flushInterval = TimeInterval.infinity
        output.start()
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

        let expectation = self.expectation(description: "async writing")
        output.writeCallback = {
            expectation.fulfill()
        }
        output.waitUntilCurrentCompletionBlock = { [weak self] in
            self?.wait(for: [expectation], timeout: 1.0)
        }

        let storedLogs: Set<LogEntry> = Set((0..<10).map { _ in makeLog() })
        logStore.add(storedLogs, for: "pv_TestingBufferedOutput", completion: nil)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)
        XCTAssertEqual(output.calledWriteCount, 0)

        output.resume()
        output.waitUntilCurrentQueuedJobFinished()

        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 1)
    }

    func testBufferedOutputSendBufferedLogs() {
        output.configuration.logEntryCountLimit = 10

        let expectation = self.expectation(description: "async writing")
        output.writeCallback = {
            expectation.fulfill()
        }
        output.waitUntilCurrentCompletionBlock = { [weak self] in
            self?.wait(for: [expectation], timeout: 1.0)
        }

        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)

        output.emit(log: makeLog())
        output.sendBufferedLogs()
        output.waitUntilCurrentQueuedJobFinished()

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
        wait(for: [expectation], timeout: 10.0)
    }

    func testBufferedOutputNotFlushed() {
        output.configuration.logEntryCountLimit = 10
        output.configuration.flushInterval = 10
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)
        output.emit(log: makeLog())
        XCTAssertEqual(output.calledWriteCount, 0)

        output.writeCallback = {
            XCTFail("writeBufferedLogs should not be called")
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

        var expectation = self.expectation(description: "async writing")
        output.writeCallback = {
            expectation.fulfill()
        }
        output.waitUntilCurrentCompletionBlock = { [weak self] in
            self?.wait(for: [expectation], timeout: 5.0)
        }

        XCTAssertEqual(output.calledWriteCount, 0)
        for _ in 0..<10 {
            output.emit(log: makeLog())
        }
        output.waitUntilCurrentQueuedJobFinished()

        XCTAssertEqual(output.calledWriteCount, 1)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)

        expectation = self.expectation(description: "retry writeChunk")
        output.writeCallback = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(output.calledWriteCount, 2)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)

        expectation = self.expectation(description: "retry writeChunk")
        output.writeCallback = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(output.calledWriteCount, 3)
        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 10)

        expectation = self.expectation(description: "retry writeChunk")
        output.writeCallback = {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
        XCTAssertEqual(output.calledWriteCount, 4)
    }

    func testParallelWrite() {
        output.configuration.logEntryCountLimit = 2
        output.configuration.retryLimit = 3
        let testIndices = 0..<1000
        let expectedWriteCount = 500

        XCTAssertEqual(logStore.logs(for: "pv_TestingBufferedOutput").count, 0)
        XCTAssertEqual(output.calledWriteCount, 0)

        let expectation = self.expectation(description: "async writing")
        expectation.expectedFulfillmentCount = expectedWriteCount
        output.waitUntilCurrentCompletionBlock = { [weak self] in
            self?.wait(for: [expectation], timeout: 20.0)
        }

        var writeCallbackCalledCount = 0
        output.writeCallback = {
            DispatchQueue.main.async {
                writeCallbackCalledCount += 1
                expectation.fulfill()
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        for _ in testIndices {
            DispatchQueue.global(qos: .background).async {
                self.output.emit(log: makeLog())
                semaphore.signal()
            }
        }

        for _ in testIndices {
            semaphore.wait()
        }

        output.resume()
        output.waitUntilCurrentQueuedJobFinished()

        XCTAssertEqual(output.calledWriteCount, expectedWriteCount)
        XCTAssertEqual(writeCallbackCalledCount, expectedWriteCount)
    }

    override func tearDown() {
        output.writeCallback = nil

        output.suspend()
        logStore.flush()
    }
}

class BufferedOutputDispatchQueueTests: XCTestCase {

    func testFlushIntervalOnDifferentDispatchQueue() {
        let exp = expectation(description: #function)
        let dispatchQueue = DispatchQueue(label: "com.cookpad.Puree.Logger", qos: .background)

        dispatchQueue.async {
            let logStore = InMemoryLogStore()
            let output = TestingBufferedOutput(logStore: logStore, tagPattern: TagPattern(string: "pv")!)
            output.configuration = BufferedOutput.Configuration(logEntryCountLimit: 5, flushInterval: 0, retryLimit: 3)
            output.start()

            output.emit(log: makeLog())

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                XCTAssertEqual(output.calledWriteCount, 1)
                exp.fulfill()
            }
        }

        waitForExpectations(timeout: 10.0)
    }
}
