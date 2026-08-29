import XCTest
@testable import Codexer

final class AppUpdatePresentationTests: XCTestCase {
    func testUpdateCheckFrequenciesUseSupportedSparkleIntervals() {
        XCTAssertEqual(AppUpdateCheckFrequency.hourly.rawValue, 3_600)
        XCTAssertEqual(AppUpdateCheckFrequency.everySixHours.rawValue, 21_600)
        XCTAssertEqual(AppUpdateCheckFrequency.daily.rawValue, 86_400)
        XCTAssertEqual(AppUpdateCheckFrequency.weekly.rawValue, 604_800)
    }

    func testUpdateCheckFrequencyMapsPersistedIntervalsToClosestChoice() {
        XCTAssertEqual(AppUpdateCheckFrequency.closest(to: 3_600), .hourly)
        XCTAssertEqual(AppUpdateCheckFrequency.closest(to: 20_000), .everySixHours)
        XCTAssertEqual(AppUpdateCheckFrequency.closest(to: 90_000), .daily)
        XCTAssertEqual(AppUpdateCheckFrequency.closest(to: 500_000), .weekly)
    }

    func testAvailableUpdateIsVisibleAndActionable() {
        let presentation = AppUpdatePresentation.available(version: "1.2.3")

        XCTAssertTrue(presentation.isVisible)
        XCTAssertFalse(presentation.showsProgress)
        XCTAssertTrue(presentation.usesCompactAvailableStyle)
        XCTAssertTrue(presentation.allowsAction)
        XCTAssertEqual(presentation.buttonTitle, "Update")
        XCTAssertEqual(presentation.version, "1.2.3")
    }

    func testActiveUpdateStagesExposeProgressState() {
        let stages: [AppUpdatePresentation] = [
            .downloading(version: "1.2.3"),
            .preparingInstallation(version: "1.2.3"),
            .installing(version: "1.2.3")
        ]

        XCTAssertTrue(stages.allSatisfy(\.isVisible))
        XCTAssertTrue(stages.allSatisfy(\.showsProgress))
        XCTAssertTrue(stages.allSatisfy { !$0.usesCompactAvailableStyle })
        XCTAssertTrue(stages.allSatisfy { !$0.allowsAction })
    }

    func testPresentedSparkleWindowKeepsCompactUpdateStyle() {
        let presentation = AppUpdatePresentation.presenting(version: "1.2.3")

        XCTAssertTrue(presentation.isVisible)
        XCTAssertFalse(presentation.showsProgress)
        XCTAssertTrue(presentation.usesCompactAvailableStyle)
        XCTAssertFalse(presentation.allowsAction)
        XCTAssertEqual(presentation.buttonTitle, "Update")
    }

    func testSparkleWindowCompactsDownloadAndInstallProgress() {
        let stages: [AppUpdatePresentation] = [
            .downloading(version: "1.2.3"),
            .preparingInstallation(version: "1.2.3"),
            .installing(version: "1.2.3"),
            .failed(version: "1.2.3")
        ]

        XCTAssertTrue(stages.allSatisfy {
            $0.keepingCompact(whileStandardWindowIsActive: true)
                == .presenting(version: "1.2.3")
        })
        XCTAssertEqual(
            AppUpdatePresentation.downloading(version: "1.2.3")
                .keepingCompact(whileStandardWindowIsActive: false),
            .downloading(version: "1.2.3")
        )
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
