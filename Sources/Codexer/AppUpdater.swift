import Foundation
import Sparkle

@MainActor
final class AppUpdater: ObservableObject {
    let controller: SPUStandardUpdaterController
    let isConfigured: Bool

    init(bundle: Bundle = .main) {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isConfigured = feedURL?.hasPrefix("https://") == true && !(publicKey ?? "").isEmpty
        controller = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: nil,
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
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard isConfigured else { return }
        objectWillChange.send()
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard isConfigured else { return }
        objectWillChange.send()
        controller.updater.automaticallyDownloadsUpdates = enabled
    }
}
