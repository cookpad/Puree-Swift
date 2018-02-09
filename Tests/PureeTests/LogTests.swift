import Foundation
import XCTest
import Puree

class LogTests: XCTestCase {
    private func decode<T: Decodable>(_ data: Data) -> T {
        return try! JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ object: T) -> Data {
        let encoder = JSONEncoder()
        let data = try! encoder.encode(object)
        return data
    }

    func testDumpUserInfo() {
        var testLog = LogEntry(tag: "tag", date: Date())
        let userInfo: [String: Any] = [
            "key0": "hello",
            "key1": 20,
            "key2": ["a", "b"],
            "key3": true,
            "key4": ["spam": "ham"]
            ]
        testLog.userData = try! JSONSerialization.data(withJSONObject: userInfo, options: [])

        let encodedData = encode(testLog)
        let decodedLog: LogEntry = decode(encodedData)

        XCTAssertEqual(decodedLog.identifier, testLog.identifier)
        XCTAssertEqual(decodedLog.tag, "tag")
        XCTAssertEqual(decodedLog.date, testLog.date)

        guard let userData = decodedLog.userData,
            let object = try? JSONSerialization.jsonObject(with: userData, options: []),
            let decodedUserInfo = object as? [String: Any] else {
            return XCTFail("userInfo should be encoded")
        }

        XCTAssertEqual(decodedUserInfo.count, 5)
        XCTAssertEqual(decodedUserInfo["key0"] as! String, "hello")
        XCTAssertEqual(decodedUserInfo["key1"] as! Int, 20)
        XCTAssertEqual(decodedUserInfo["key2"] as! [String], ["a", "b"])
        XCTAssertEqual(decodedUserInfo["key3"] as! Bool, true)
        XCTAssertEqual(decodedUserInfo["key4"] as! [String: String], ["spam": "ham"])
    }
}
