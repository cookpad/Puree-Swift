import Foundation
import XCTest
@testable import Puree

class TagPatternTests: XCTestCase {
    func assertMatched(_ match: TagPattern.Match?, capturedString expectedCapturedString: String?) {
        if let match = match {
            if match.captured != expectedCapturedString {
                XCTFail("capturedString should be \(String(describing: expectedCapturedString)) but actually is \(String(describing: match.captured))")
            }
        } else {
            XCTFail("should have matched")
        }
    }

    func assertNotMatched(_ match: TagPattern.Match?) {
        if match != nil {
            XCTFail("should not be matched")
        }
    }

    func testMatches() {
        assertMatched(TagPattern(string: "aaa")!.match(in: "aaa"), capturedString: nil)
        assertNotMatched(TagPattern(string: "bbb")!.match(in: "aaa"))
        assertMatched(TagPattern(string: "*")!.match(in: "aaa"), capturedString: "aaa")
        assertMatched(TagPattern(string: "*")!.match(in: "bbb"), capturedString: "bbb")
        assertNotMatched(TagPattern(string: "*")!.match(in: "aaa.bbb"))
        assertMatched(TagPattern(string: "aaa.bbb")!.match(in: "aaa.bbb"), capturedString: nil)
        assertMatched(TagPattern(string: "aaa.*")!.match(in: "aaa.bbb"), capturedString: "bbb")
        assertMatched(TagPattern(string: "aaa.*")!.match(in: "aaa.ccc"), capturedString: "ccc")
        assertNotMatched(TagPattern(string: "aaa.*")!.match(in: "aaa.bbb.ccc"))
        assertNotMatched(TagPattern(string: "aaa.*.ccc")!.match(in: "aaa.bbb.ccc"))
        assertNotMatched(TagPattern(string: "aaa.*.ccc")!.match(in: "aaa.ccc.ddd"))
        assertMatched(TagPattern(string: "a.**")!.match(in: "a"), capturedString: "")
        assertMatched(TagPattern(string: "a.**")!.match(in: "a.b"), capturedString: "b")
        assertMatched(TagPattern(string: "a.**")!.match(in: "a.b.c"), capturedString: "b.c")
        assertNotMatched(TagPattern(string: "a.**")!.match(in: "b.c"))
    }

    func testInvalidPatterns() {
        XCTAssertNil(TagPattern(string: "**.**"))
        XCTAssertNil(TagPattern(string: "**.*"))
        XCTAssertNil(TagPattern(string: "*.b.*"))
        XCTAssertNil(TagPattern(string: "a.**.**"))
        XCTAssertNil(TagPattern(string: "a..b.c"))
        XCTAssertNil(TagPattern(string: ""))
    }
}
