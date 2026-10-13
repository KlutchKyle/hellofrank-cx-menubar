import XCTest
@testable import HelloFrankCore

final class SlackMessageParserTests: XCTestCase {
    func testHeaders() {
        XCTAssertEqual(SlackMessageParser.header(of: "[fix-proposal HEL-1234] Fix login")?.identifier, "HEL-1234")
        XCTAssertEqual(SlackMessageParser.header(of: "[fix-proposal HEL-1234] Fix login")?.kind, .fixProposal)
        XCTAssertEqual(SlackMessageParser.header(of: "[prod-debug HEL-77]\nRoot cause: x")?.kind, .prodDebug)
        XCTAssertEqual(SlackMessageParser.header(of: "[fix-proposal hel-5 v2] x")?.identifier, "HEL-5")
    }

    func testHeaderMustBeOnFirstLine() {
        XCTAssertNil(SlackMessageParser.header(of: "Reminder\n[fix-proposal HEL-1234]"))
        XCTAssertNil(SlackMessageParser.header(of: "see [fix-proposal HEL-1234]"))
        XCTAssertNil(SlackMessageParser.header(of: "[fix-pr HEL-1234]"))
    }

    func testFields() {
        let text = """
        [fix-proposal HEL-1234] Login loop
        *Root cause:* session_cookie is dropped on redirect
        • _Fix:_ keep the cookie
        Fix approvals: n/a
        """
        XCTAssertEqual(SlackMessageParser.field("Root cause", in: text), "session_cookie is dropped on redirect")
        XCTAssertEqual(SlackMessageParser.field("Fix", in: text), "keep the cookie")
        XCTAssertNil(SlackMessageParser.field("Risk", in: text))
    }

    func testTimestamp() {
        XCTAssertEqual(SlackMessageParser.date(fromTS: "1712345678.123456")?.timeIntervalSince1970 ?? 0, 1712345678.123456, accuracy: 0.001)
        XCTAssertNil(SlackMessageParser.date(fromTS: "nope"))
    }
}
