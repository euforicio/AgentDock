import Foundation
import CodexerCore
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    let isConfigured: Bool

    init(bundle: Bundle = .main) {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isConfigured = feedURL?.hasPrefix("https://") == true && !(publicKey ?? "").isEmpty
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: self,
            userDriverDelegate: nil
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
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateAvailable), .outcome(.succeeded), .trigger(.automatic)]
        ))
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateDownloadStarted), .trigger(.automatic)]
        ))
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateDownloaded), .outcome(.succeeded), .trigger(.automatic)]
        ))
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: Error) {
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateDownloaded), .outcome(.failed), .trigger(.automatic)]
        ))
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateInstallStarted), .trigger(.automatic)]
        ))
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .updateLifecycle,
            [.action(.updateCycleCompleted), .outcome(error == nil ? .succeeded : .failed), .trigger(.automatic)]
        ))
    }
}
