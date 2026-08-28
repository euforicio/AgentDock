import Foundation

public enum AnalyticsConsent: String, Sendable {
    case undecided
    case denied
    case granted
}

public struct AnalyticsConsentStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var consent: AnalyticsConsent {
        defaults.string(forKey: Key.consent).flatMap(AnalyticsConsent.init(rawValue:)) ?? .undecided
    }

    public var installationID: UUID? {
        guard consent == .granted,
              let value = defaults.string(forKey: Key.installationID)
        else { return nil }
        return UUID(uuidString: value)
    }

    @discardableResult
    public func grant() -> UUID {
        let identifier = defaults.string(forKey: Key.installationID)
            .flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(identifier.uuidString.lowercased(), forKey: Key.installationID)
        defaults.set(AnalyticsConsent.granted.rawValue, forKey: Key.consent)
        return identifier
    }

    public func denyAndDeleteIdentifier() {
        defaults.set(AnalyticsConsent.denied.rawValue, forKey: Key.consent)
        defaults.removeObject(forKey: Key.installationID)
    }

    public func resetDecisionAndDeleteIdentifier() {
        defaults.removeObject(forKey: Key.consent)
        defaults.removeObject(forKey: Key.installationID)
    }

    private enum Key {
        static let consent = "AgentDock.analyticsConsent.v1"
        static let installationID = "AgentDock.analyticsInstallationID.v1"
    }
}

public enum AnalyticsEventName: String, CaseIterable, Sendable {
    case appLifecycle = "app_lifecycle"
    case consentDecision = "consent_decision"
    case navigation = "navigation"
    case profileLifecycle = "profile_lifecycle"
    case providerStatus = "provider_status"
    case launcherLifecycle = "launcher_lifecycle"
    case chatUsage = "chat_usage"
    case refresh = "refresh"
    case updateLifecycle = "update_lifecycle"
    case preferenceChanged = "preference_changed"
    case error = "error"
    case performance = "performance"
    case featureAdoption = "feature_adoption"
}

public enum AnalyticsSurface: String, CaseIterable, Sendable {
    case onboarding, sidebar, overview, chats, advanced, settingsGeneral, settingsProviders
    case settingsPrivacy, settingsAbout, menu, shortcut, updater
}

public enum AnalyticsAction: String, CaseIterable, Sendable {
    case launched, becameActive, consentGranted, consentDenied
    case viewed, searched, selected, created, restored, edited, removed, deleted
    case discovered, configured, validated, opened, focused, closed
    case installed, repaired, uninstalled
    case listed, transcriptOpened, transcriptPageLoaded, metadataViewed, metadataCopied
    case manualRefresh, automaticRefresh
    case updateChecked, updateAvailable, updateDownloadStarted, updateDownloaded
    case updateInstallStarted, updateCycleCompleted, updatePreferenceChanged
    case appearanceChanged, defaultViewChanged, activityRefreshChanged, statusVisibilityChanged
}

public enum AnalyticsOutcome: String, CaseIterable, Sendable {
    case succeeded, failed, cancelled, unavailable, rejected, noChange
}

public enum AnalyticsProvider: String, CaseIterable, Sendable {
    case codex, claude, mixed, none
}

public enum AnalyticsTrigger: String, CaseIterable, Sendable {
    case firstLaunch, user, automatic, applicationMenu, profileShortcut, settings
}

public enum AnalyticsFeature: String, CaseIterable, Sendable {
    case managedProfiles, officialApps, shortcuts, chats, transcriptPagination
    case localActivity, rateLimits, providerConfiguration, updates, privacyControls
}

public enum AnalyticsErrorCode: String, CaseIterable, Sendable {
    case storeUnavailable, persistenceFailed, providerNotFound, signatureRejected
    case launchFailed, closeFailed, shortcutFailed, transcriptUnavailable
    case refreshFailed, updateUnavailable, invalidConfiguration, operationBusy, unknownSafe
}

public enum AnalyticsDurationBucket: String, CaseIterable, Sendable {
    case under100ms, ms100To499, ms500To1999, seconds2To9, seconds10Plus

    public init(milliseconds: Int) {
        switch max(0, milliseconds) {
        case ..<100: self = .under100ms
        case ..<500: self = .ms100To499
        case ..<2_000: self = .ms500To1999
        case ..<10_000: self = .seconds2To9
        default: self = .seconds10Plus
        }
    }
}

public enum AnalyticsCountBucket: String, CaseIterable, Sendable {
    case zero, one, twoToFive, sixToTwenty, twentyOnePlus

    public init(_ count: Int) {
        switch max(0, count) {
        case 0: self = .zero
        case 1: self = .one
        case 2...5: self = .twoToFive
        case 6...20: self = .sixToTwenty
        default: self = .twentyOnePlus
        }
    }
}

public enum AnalyticsPropertyKey: String, Sendable {
    case surface, action, outcome, provider, trigger, feature, errorCode
    case durationBucket, countBucket, enabled
}

public enum AnalyticsProperty: Sendable {
    case surface(AnalyticsSurface)
    case action(AnalyticsAction)
    case outcome(AnalyticsOutcome)
    case provider(AnalyticsProvider)
    case trigger(AnalyticsTrigger)
    case feature(AnalyticsFeature)
    case errorCode(AnalyticsErrorCode)
    case durationBucket(AnalyticsDurationBucket)
    case countBucket(AnalyticsCountBucket)
    case enabled(Bool)

    var key: AnalyticsPropertyKey {
        switch self {
        case .surface: .surface
        case .action: .action
        case .outcome: .outcome
        case .provider: .provider
        case .trigger: .trigger
        case .feature: .feature
        case .errorCode: .errorCode
        case .durationBucket: .durationBucket
        case .countBucket: .countBucket
        case .enabled: .enabled
        }
    }

    var jsonValue: Any {
        switch self {
        case let .surface(value): value.rawValue
        case let .action(value): value.rawValue
        case let .outcome(value): value.rawValue
        case let .provider(value): value.rawValue
        case let .trigger(value): value.rawValue
        case let .feature(value): value.rawValue
        case let .errorCode(value): value.rawValue
        case let .durationBucket(value): value.rawValue
        case let .countBucket(value): value.rawValue
        case let .enabled(value): value
        }
    }
}

public struct AnalyticsEvent: Sendable {
    public let name: AnalyticsEventName
    public let properties: [AnalyticsProperty]

    public init?(_ name: AnalyticsEventName, _ properties: [AnalyticsProperty]) {
        let keys = properties.map(\.key)
        guard properties.count <= 8,
              Set(keys).count == keys.count,
              Set(keys).isSubset(of: name.allowedPropertyKeys),
              name.requiredPropertyKeys.isSubset(of: Set(keys))
        else { return nil }
        self.name = name
        self.properties = properties
    }
}

private extension AnalyticsEventName {
    var requiredPropertyKeys: Set<AnalyticsPropertyKey> {
        switch self {
        case .appLifecycle, .consentDecision, .navigation, .profileLifecycle,
             .providerStatus, .launcherLifecycle, .chatUsage, .refresh,
             .updateLifecycle, .preferenceChanged, .featureAdoption:
            [.action]
        case .error: [.errorCode]
        case .performance: [.durationBucket]
        }
    }

    var allowedPropertyKeys: Set<AnalyticsPropertyKey> {
        switch self {
        case .appLifecycle: [.action, .trigger, .countBucket]
        case .consentDecision: [.action, .surface]
        case .navigation: [.action, .surface, .provider]
        case .profileLifecycle: [.action, .outcome, .provider, .countBucket, .durationBucket]
        case .providerStatus: [.action, .outcome, .provider]
        case .launcherLifecycle: [.action, .outcome, .provider, .trigger, .durationBucket, .countBucket]
        case .chatUsage: [.action, .outcome, .provider, .countBucket, .durationBucket]
        case .refresh: [.action, .outcome, .surface, .trigger, .countBucket, .durationBucket]
        case .updateLifecycle: [.action, .outcome, .trigger, .enabled]
        case .preferenceChanged: [.action, .surface, .enabled]
        case .error: [.errorCode, .surface, .provider, .action]
        case .performance: [.durationBucket, .surface, .action, .provider, .countBucket]
        case .featureAdoption: [.action, .feature, .surface, .provider]
        }
    }
}

public struct ProductAnalyticsConfiguration: Equatable, Sendable {
    public let projectToken: String
    public let host: URL

    public init?(projectToken: String, host: String) {
        guard projectToken.range(
            of: #"^phc_[A-Za-z0-9_-]{8,128}$"#,
            options: .regularExpression
        ) != nil,
        var components = URLComponents(string: host),
        components.scheme == "https",
        components.host != nil,
        components.user == nil,
        components.password == nil,
        components.port == nil,
        components.path.isEmpty || components.path == "/",
        components.query == nil,
        components.fragment == nil
        else { return nil }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/batch/"
        guard let captureURL = components.url else { return nil }
        self.projectToken = projectToken
        self.host = captureURL
    }

    public init?(bundle: Bundle) {
        guard let token = bundle.object(forInfoDictionaryKey: "AgentDockPostHogProjectToken") as? String,
              let host = bundle.object(forInfoDictionaryKey: "AgentDockPostHogHost") as? String
        else { return nil }
        self.init(projectToken: token, host: host)
    }
}

public final class ProductAnalytics: @unchecked Sendable {
    public static let shared = ProductAnalytics()

    private let consentStore: AnalyticsConsentStore
    private let configuration: ProductAnalyticsConfiguration?
    private let session: URLSession
    private let appVersion: String
    private let osMajorVersion: Int
    private let architecture: String
    private let deliveryQueue = DispatchQueue(label: "dev.euforic.agentdock.analytics")
    private var pendingEvents: [AnalyticsEvent] = []
    private var activeTasks: [UUID: URLSessionDataTask] = [:]
    private var scheduledFlush: DispatchWorkItem?
    private static let flushAt = 12
    private static let maximumPendingEvents = 48
    private static let flushDelay: TimeInterval = 5

    public init(
        consentStore: AnalyticsConsentStore = AnalyticsConsentStore(),
        configuration: ProductAnalyticsConfiguration? = ProductAnalyticsConfiguration(bundle: .main),
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
        osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        architecture: String = ProductAnalytics.currentArchitecture
    ) {
        self.consentStore = consentStore
        self.configuration = configuration
        self.appVersion = Self.safeVersion(appVersion)
        self.osMajorVersion = max(0, min(osMajorVersion, 999))
        self.architecture = ["arm64", "x86_64"].contains(architecture) ? architecture : "other"
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.timeoutIntervalForRequest = 10
        sessionConfiguration.timeoutIntervalForResource = 15
        sessionConfiguration.waitsForConnectivity = false
        self.session = URLSession(configuration: sessionConfiguration)
    }

    public var isConfigured: Bool { configuration != nil }
    public var consent: AnalyticsConsent { consentStore.consent }

    @discardableResult
    public func grantConsent(surface: AnalyticsSurface) -> UUID {
        let identifier = consentStore.grant()
        capture(AnalyticsEvent(.consentDecision, [.action(.consentGranted), .surface(surface)]))
        if surface == .onboarding {
            capture(AnalyticsEvent(.appLifecycle, [.action(.launched), .trigger(.firstLaunch)]))
        }
        return identifier
    }

    public func denyConsent() {
        consentStore.denyAndDeleteIdentifier()
        deliveryQueue.sync {
            scheduledFlush?.cancel()
            scheduledFlush = nil
            pendingEvents.removeAll(keepingCapacity: false)
            activeTasks.values.forEach { $0.cancel() }
            activeTasks.removeAll(keepingCapacity: false)
        }
    }

    public func capture(_ event: AnalyticsEvent?) {
        guard let event, payload(for: event) != nil else { return }
        deliveryQueue.async { [weak self] in
            guard let self, self.consentStore.consent == .granted else { return }
            if self.pendingEvents.count == Self.maximumPendingEvents {
                self.pendingEvents.removeFirst()
            }
            self.pendingEvents.append(event)
            if self.pendingEvents.count >= Self.flushAt {
                self.flushLocked()
            } else if self.scheduledFlush == nil {
                let work = DispatchWorkItem { [weak self] in self?.flushLocked() }
                self.scheduledFlush = work
                self.deliveryQueue.asyncAfter(deadline: .now() + Self.flushDelay, execute: work)
            }
        }
    }

    func payload(for event: AnalyticsEvent) -> [String: Any]? {
        guard let configuration, consentStore.consent == .granted,
              let identifier = consentStore.installationID
        else { return nil }
        var properties: [String: Any] = [
            "token": configuration.projectToken,
            "distinct_id": identifier.uuidString.lowercased(),
            "$geoip_disable": true,
            "$process_person_profile": false,
            "schema_version": 1,
            "app_version": appVersion,
            "os_major": osMajorVersion,
            "architecture": architecture
        ]
        for property in event.properties {
            properties[property.key.rawValue] = property.jsonValue
        }
        return ["event": event.name.rawValue, "properties": properties]
    }

    func deliverySnapshot() -> (pending: Int, active: Int) {
        deliveryQueue.sync { (pendingEvents.count, activeTasks.count) }
    }

    private func flushLocked() {
        dispatchPrecondition(condition: .onQueue(deliveryQueue))
        scheduledFlush?.cancel()
        scheduledFlush = nil
        guard consentStore.consent == .granted, let configuration, !pendingEvents.isEmpty else {
            pendingEvents.removeAll(keepingCapacity: false)
            return
        }
        let batch = pendingEvents.compactMap(payload(for:))
        pendingEvents.removeAll(keepingCapacity: true)
        guard !batch.isEmpty else { return }
        let body: [String: Any] = ["api_key": configuration.projectToken, "batch": batch]
        guard let data = try? JSONSerialization.data(withJSONObject: body), data.count <= 64 * 1_024 else { return }
        var request = URLRequest(url: configuration.host, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let deliveryID = UUID()
        let task = session.dataTask(with: request) { [weak self] _, _, _ in
            self?.deliveryQueue.async { [weak self] in
                self?.activeTasks.removeValue(forKey: deliveryID)
            }
        }
        activeTasks[deliveryID] = task
        task.resume()
    }

    private static func safeVersion(_ value: String) -> String {
        let permitted = value.prefix(32).filter { $0.isNumber || $0 == "." || $0 == "-" }
        return permitted.isEmpty ? "development" : String(permitted)
    }

    public static var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "other"
        #endif
    }
}
