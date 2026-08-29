import XCTest
@testable import Codexer

final class AppUpdatePresentationTests: XCTestCase {
    func testAvailableUpdateIsVisibleAndActionable() {
        let presentation = AppUpdatePresentation.available(version: "1.2.3")

        XCTAssertTrue(presentation.isVisible)
        XCTAssertFalse(presentation.showsProgress)
        XCTAssertTrue(presentation.usesCompactAvailableStyle)
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
        XCTAssertTrue(stages.allSatisfy { !$0.usesCompactAvailableStyle })
    }

    func testFailedUpdateOffersRetryWithoutLosingVersion() {
        let presentation = AppUpdatePresentation.failed(version: "1.2.3")

        XCTAssertTrue(presentation.isVisible)
        XCTAssertFalse(presentation.showsProgress)
        XCTAssertFalse(presentation.usesCompactAvailableStyle)
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

    func testDismissedUpdateCycleRestoresPersistentAvailablePill() {
        let completed = AppUpdatePresentation
            .preparingInstallation(version: "1.2.3")
            .completingUpdateCycle(hadError: false)

        XCTAssertEqual(completed, .available(version: "1.2.3"))
    }

    func testFailedUpdateCycleKeepsRetryAction() {
        let completed = AppUpdatePresentation
            .downloading(version: "1.2.3")
            .completingUpdateCycle(hadError: true)

        XCTAssertEqual(completed, .failed(version: "1.2.3"))
    }
}
