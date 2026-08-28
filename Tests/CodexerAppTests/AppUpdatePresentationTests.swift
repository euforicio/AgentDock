import XCTest
@testable import Codexer

final class AppUpdatePresentationTests: XCTestCase {
    func testAvailableUpdateIsVisibleAndActionable() {
        let presentation = AppUpdatePresentation.available(version: "1.2.3")

        XCTAssertTrue(presentation.isVisible)
        XCTAssertFalse(presentation.showsProgress)
        XCTAssertEqual(presentation.buttonTitle, "Update")
        XCTAssertEqual(presentation.version, "1.2.3")
    }

    func testActiveUpdateStagesExposeProgressState() {
        let stages: [AppUpdatePresentation] = [
            .presenting(version: "1.2.3"),
            .downloading(version: "1.2.3"),
            .preparingInstallation(version: "1.2.3"),
            .installing(version: "1.2.3")
        ]

        XCTAssertTrue(stages.allSatisfy(\.isVisible))
        XCTAssertTrue(stages.allSatisfy(\.showsProgress))
    }

    func testFailedUpdateOffersRetryWithoutLosingVersion() {
        let presentation = AppUpdatePresentation.failed(version: "1.2.3")

        XCTAssertTrue(presentation.isVisible)
        XCTAssertFalse(presentation.showsProgress)
        XCTAssertEqual(presentation.buttonTitle, "Try Again")
        XCTAssertEqual(presentation.version, "1.2.3")
    }

    func testHiddenUpdateDoesNotExposeAction() {
        let presentation = AppUpdatePresentation.hidden

        XCTAssertFalse(presentation.isVisible)
        XCTAssertFalse(presentation.showsProgress)
        XCTAssertEqual(presentation.buttonTitle, "")
        XCTAssertNil(presentation.version)
    }
}
