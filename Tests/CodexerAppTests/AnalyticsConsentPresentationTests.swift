import XCTest
@testable import Codexer

@MainActor
final class AnalyticsConsentPresentationTests: XCTestCase {
    func testConsentPromptPresentationIsDisabled() {
        let presentationEnabled = AnalyticsConsentView.presentationEnabled
        XCTAssertFalse(presentationEnabled)
    }
}
