import Combine
import Foundation
import CodexerCore
import Sparkle

enum AppUpdatePresentation: Equatable {
    case hidden
    case available(version: String)
    case presenting(version: String)
    case downloading(version: String)
    case preparingInstallation(version: String)
    case installing(version: String)
    case failed(version: String)

    var isVisible: Bool {
        self != .hidden
    }

    var showsProgress: Bool {
        switch self {
        case .presenting, .downloading, .preparingInstallation, .installing:
            true
        case .hidden, .available, .failed:
            false
        }
    }

    var usesCompactAvailableStyle: Bool {
        if case .available = self {
            true
        } else {
            false
        }
    }

    var buttonTitle: String {
        switch self {
        case .hidden:
            ""
        case .available:
            "Update"
        case .presenting:
            "Opening…"
        case .downloading:
            "Downloading…"
        case .preparingInstallation:
            "Preparing…"
        case .installing:
            "Installing…"
        case .failed:
            "Try Again"
        }
    }

    var version: String? {
        switch self {
        case .hidden:
            nil
        case let .available(version), let .presenting(version), let .downloading(version),
             let .preparingInstallation(version), let .installing(version), let .failed(version):
            version
        }
    }

    func completingUpdateCycle(hadError: Bool) -> AppUpdatePresentation {
        switch self {
        case .hidden:
            .hidden
        case let .available(version), let .presenting(version), let .downloading(version),
             let .preparingInstallation(version):
            hadError ? .failed(version: version) : .available(version: version)
        case .installing, .failed:
            self
        }
    }
}

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    @Published private(set) var presentation = AppUpdatePresentation.hidden
    let isConfigured: Bool

    init(bundle: Bundle = .main) {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isConfigured = feedURL?.hasPrefix("https://") == true && !(publicKey ?? "").isEmpty
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    var automaticallyChecksForUpdates: Bool {
        isConfigured && controller.updater.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        isConfigured && controller.updater.automaticallyDownloadsUpdates
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateChecked), .trigger(.user)]
        ))
        controller.checkForUpdates(nil)
    }

    func installAvailableUpdate() {
        guard isConfigured, let version = presentation.version, !presentation.showsProgress else { return }
        presentation = .presenting(version: version)
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateChecked), .trigger(.user)]
        ))
        // Sparkle retains the scheduled update session. Checking again brings its
        // signed, native download and installation UI into focus.
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isConfigured else { return }
        objectWillChange.send()
        controller.updater.automaticallyChecksForUpdates = enabled
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updatePreferenceChanged), .trigger(.settings), .enabled(enabled)]
        ))
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard isConfigured else { return }
        objectWillChange.send()
        controller.updater.automaticallyDownloadsUpdates = enabled
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updatePreferenceChanged), .trigger(.settings), .enabled(enabled)]
        ))
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        presentation = .available(version: item.displayVersionString)
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateAvailable), .outcome(.succeeded), .trigger(.automatic)]
        ))
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        presentation = .downloading(version: item.displayVersionString)
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateDownloadStarted), .trigger(.automatic)]
        ))
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        presentation = .preparingInstallation(version: item.displayVersionString)
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateDownloaded), .outcome(.succeeded), .trigger(.automatic)]
        ))
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        presentation = .failed(version: item.displayVersionString)
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateDownloaded), .outcome(.failed), .trigger(.automatic)]
        ))
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        presentation = .installing(version: item.displayVersionString)
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateInstallStarted), .trigger(.automatic)]
        ))
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        presentation = presentation.completingUpdateCycle(hadError: error != nil)
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateCycleCompleted), .outcome(error == nil ? .succeeded : .failed), .trigger(.automatic)]
        ))
    }


    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate {
            presentation = .available(version: update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        if presentation == .available(version: update.displayVersionString) {
            presentation = .presenting(version: update.displayVersionString)
        }
    }
}
