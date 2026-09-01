import Foundation

public enum AgentDockAppearance: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        rawValue.capitalized
    }
}

public enum AgentDockDefaultView: String, Codable, CaseIterable, Sendable {
    case lastOpened
    case overview
    case chats

    public var displayName: String {
        switch self {
        case .lastOpened: "Last Opened Profile"
        case .overview: "Overview"
        case .chats: "Chats"
        }
    }
}

public struct AgentDockPreferences: Equatable, Sendable {
    public var appearance: AgentDockAppearance
    public var defaultView: AgentDockDefaultView
    public var refreshProfileActivity: Bool
    public var refreshIntervalMinutes: Int
    public var showStatusInProfileList: Bool
    public var defaultCodexConfigProfile: CodexConfigProfile? = nil

    public static let defaults = AgentDockPreferences(
        appearance: .system,
        defaultView: .lastOpened,
        refreshProfileActivity: true,
        refreshIntervalMinutes: 5,
        showStatusInProfileList: true,
        defaultCodexConfigProfile: nil
    )
}

public struct AgentDockPreferencesStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AgentDockPreferences {
        let standard = AgentDockPreferences.defaults
        let appearance = defaults.string(forKey: Key.appearance)
            .flatMap(AgentDockAppearance.init(rawValue:)) ?? standard.appearance
        let defaultView = defaults.string(forKey: Key.defaultView)
            .flatMap(AgentDockDefaultView.init(rawValue:)) ?? standard.defaultView
        let refresh = defaults.object(forKey: Key.refreshProfileActivity) == nil
            ? standard.refreshProfileActivity
            : defaults.bool(forKey: Key.refreshProfileActivity)
        let storedInterval = defaults.integer(forKey: Key.refreshIntervalMinutes)
        let interval = Self.allowedIntervals.contains(storedInterval)
            ? storedInterval
            : standard.refreshIntervalMinutes
        let showStatus = defaults.object(forKey: Key.showStatusInProfileList) == nil
            ? standard.showStatusInProfileList
            : defaults.bool(forKey: Key.showStatusInProfileList)
        let defaultCodexConfigProfile = defaults.string(forKey: Key.defaultCodexConfigProfile)
            .flatMap { try? CodexConfigProfile(validating: $0) }
        return AgentDockPreferences(
            appearance: appearance,
            defaultView: defaultView,
            refreshProfileActivity: refresh,
            refreshIntervalMinutes: interval,
            showStatusInProfileList: showStatus,
            defaultCodexConfigProfile: defaultCodexConfigProfile
        )
    }

    public func save(_ preferences: AgentDockPreferences) {
        defaults.set(preferences.appearance.rawValue, forKey: Key.appearance)
        defaults.set(preferences.defaultView.rawValue, forKey: Key.defaultView)
        defaults.set(preferences.refreshProfileActivity, forKey: Key.refreshProfileActivity)
        defaults.set(
            Self.allowedIntervals.contains(preferences.refreshIntervalMinutes)
                ? preferences.refreshIntervalMinutes
                : AgentDockPreferences.defaults.refreshIntervalMinutes,
            forKey: Key.refreshIntervalMinutes
        )
        defaults.set(preferences.showStatusInProfileList, forKey: Key.showStatusInProfileList)
        defaults.set(
            preferences.defaultCodexConfigProfile?.name,
            forKey: Key.defaultCodexConfigProfile
        )
    }

    public func restoreDefaults() {
        [
            Key.appearance,
            Key.defaultView,
            Key.refreshProfileActivity,
            Key.refreshIntervalMinutes,
            Key.showStatusInProfileList,
            Key.defaultCodexConfigProfile
        ].forEach(defaults.removeObject(forKey:))
    }

    public static let allowedIntervals = [1, 5, 15, 30, 60]

    private enum Key {
        static let appearance = "AgentDock.appearance"
        static let defaultView = "AgentDock.defaultView"
        static let refreshProfileActivity = "AgentDock.refreshProfileActivity"
        static let refreshIntervalMinutes = "AgentDock.refreshIntervalMinutes"
        static let showStatusInProfileList = "AgentDock.showStatusInProfileList"
        static let defaultCodexConfigProfile = "AgentDock.defaultCodexConfigProfile"
    }
}
