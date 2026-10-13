import XCTest
@testable import HelloFrankCore

final class MarkerParserTests: XCTestCase {
    func testFindsEachMarker() {
        for marker in Marker.allCases {
            XCTAssertEqual(MarkerParser.markers(in: "Text\n<!-- \(marker.rawValue) -->"), [marker], marker.rawValue)
        }
    }

    func testFixPRIsNotConfusedWithFixProposal() {
        XCTAssertEqual(MarkerParser.markers(in: "<!-- fix-proposal -->"), [.fixProposal])
        XCTAssertEqual(MarkerParser.markers(in: "<!-- fix-pr -->"), [.fixPR])
    }

    func testToleratesSpacingCaseAndTrailingText() {
        XCTAssertEqual(MarkerParser.markers(in: "<!--cx-triage-->"), [.cxTriage])
        XCTAssertEqual(MarkerParser.markers(in: "<!--   FIX-DEBUG   -->"), [.fixDebug])
        XCTAssertEqual(MarkerParser.markers(in: "<!-- fix-proposal HEL-1234 -->"), [.fixProposal])
    }

    func testMultipleMarkersAndUnknownComments() {
        let body = "<!-- cx-triage --> hi <!-- something-else --> <!-- toni-bot -->"
        XCTAssertEqual(MarkerParser.markers(in: body), [.cxTriage, .toniBot])
        XCTAssertTrue(MarkerParser.markers(in: "A plain human comment").isEmpty)
        XCTAssertTrue(MarkerParser.markers(in: "cx-triage mentioned without a comment").isEmpty)
    }

    func testPRURLPrefersGitHubPullLink() {
        let body = "<!-- fix-pr -->\nDraft PR: https://github.com/hellofrank/chief-suite-app/pull/812 (see https://example.com/doc)"
        XCTAssertEqual(MarkerParser.prURL(in: body)?.absoluteString, "https://github.com/hellofrank/chief-suite-app/pull/812")
    }

    func testPRURLFallsBackToFirstURL() {
        XCTAssertEqual(MarkerParser.prURL(in: "<!-- fix-pr --> PR at https://git.example.com/pr/9.")?.absoluteString,
                       "https://git.example.com/pr/9")
        XCTAssertNil(MarkerParser.prURL(in: "<!-- fix-pr --> no link"))
    }

    func testQuestionForKyle() {
        let body = """
        <!-- cx-triage -->
        Summary of the issue.

        **Question for Kyle:** Should we refund the customer?
        Or offer credit?

        Next steps: none.
        """
        XCTAssertEqual(MarkerParser.questionForKyle(in: body), "Should we refund the customer?\nOr offer credit?")
        XCTAssertNil(MarkerParser.questionForKyle(in: "<!-- cx-triage --> No questions here."))
        XCTAssertEqual(MarkerParser.questionForKyle(in: "question for kyle: lower case?"), "lower case?")
    }
}
