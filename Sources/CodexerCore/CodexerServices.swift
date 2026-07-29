import Foundation

public protocol CodexInstanceManaging: Sendable {
    func statuses(
        for profiles: [CodexProfile],
        codexAppURL: URL
    ) async throws -> [CodexProfile.ID: CodexInstanceStatus]
    func open(profile: CodexProfile, codexAppURL: URL) async throws -> CodexOpenOutcome
    func close(profile: CodexProfile, codexAppURL: URL) async throws -> CodexCloseOutcome
    func stockStatus(codexAppURL: URL) async throws -> CodexInstanceStatus
    func openStock(codexAppURL: URL) async throws -> CodexOpenOutcome
    func validateCodexApp(at url: URL) async throws
}

extension CodexInstanceController: CodexInstanceManaging {}

public protocol DesktopInstanceManaging: Sendable {
    func statuses(
        for profiles: [CodexProfile],
        appURLs: [DesktopProduct: URL]
    ) async throws -> [CodexProfile.ID: CodexInstanceStatus]
    func open(profile: CodexProfile, appURL: URL) async throws -> CodexOpenOutcome
    func close(profile: CodexProfile, appURL: URL) async throws -> CodexCloseOutcome
    func stockStatus(
        product: DesktopProduct,
        appURL: URL
    ) async throws -> CodexInstanceStatus
    func openStock(
        product: DesktopProduct,
        appURL: URL
    ) async throws -> CodexOpenOutcome
    func validateApp(product: DesktopProduct, at url: URL) async throws
}

extension DesktopInstanceController: DesktopInstanceManaging {}

public protocol ProfileStatsScanning: Sendable {
    func stats(for profile: CodexProfile, now: Date) -> ProfileStats
    func stats(codexHomeURL: URL, dataRootURL: URL, now: Date) -> ProfileStats
}

extension ProfileStatsScanner: ProfileStatsScanning {}

public protocol ProfileRateLimitFetching: Sendable {
    func fetchRateLimits(for profile: CodexProfile, codexAppURL: URL) -> ProfileRateLimits
    func fetchRateLimits(codexHomeURL: URL, codexAppURL: URL) -> ProfileRateLimits
}

extension AppServerRateLimitClient: ProfileRateLimitFetching {}

public protocol ShortcutManaging: Sendable {
    func installShortcut(for profile: CodexProfile, codexAppURL: URL) throws
    func removeShortcut(for profile: CodexProfile) throws
    func shortcutExists(for profile: CodexProfile) -> Bool
}

extension ShortcutInstaller: ShortcutManaging {}
