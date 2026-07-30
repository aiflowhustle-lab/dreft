import XCTest
@testable import Dreft

final class NoteFindReplaceSupportTests: XCTestCase {
    func testFindNextWrapsFromCaret() {
        let text = "alpha beta alpha"
        let first = NoteFindReplaceSupport.findNext(in: text, query: "alpha", after: 0)!
        XCTAssertEqual(first, NSRange(location: 0, length: 5))
        let second = NoteFindReplaceSupport.findNext(in: text, query: "alpha", after: first.location + first.length)!
        XCTAssertEqual(second, NSRange(location: 11, length: 5))
        let wrapped = NoteFindReplaceSupport.findNext(in: text, query: "alpha", after: second.location + second.length)!
        XCTAssertEqual(wrapped, NSRange(location: 0, length: 5))
    }

    func testFindPreviousWrapsToEnd() {
        let text = "alpha beta alpha"
        let previous = NoteFindReplaceSupport.findPrevious(in: text, query: "alpha", before: 0)!
        XCTAssertEqual(previous, NSRange(location: 11, length: 5))
    }

    func testReplaceCurrentUsesSelectionWhenItMatches() {
        let text = "hello world"
        let range = NSRange(location: 6, length: 5)
        let result = NoteFindReplaceSupport.replaceCurrent(
            in: text,
            query: "world",
            replacement: "there",
            selectedRange: range
        )
        XCTAssertEqual(result?.text, "hello there")
        XCTAssertEqual(result?.selectedRange, NSRange(location: 11, length: 0))
    }

    func testReplaceAllUsesNSStringRanges() {
        let text = "👋 hi 👋"
        let replaced = NoteFindReplaceSupport.replaceAll(in: text, query: "👋", replacement: "!")
        XCTAssertEqual(replaced, "! hi !")
    }

    func testCaseInsensitiveFind() {
        let text = "Hello HELLO"
        let options: NoteFindReplaceOptions = [.caseInsensitive]
        XCTAssertEqual(NoteFindReplaceSupport.matchCount(of: "hello", in: text, options: options), 2)
    }
}
