import XCTest
@testable import CodexerCore

final class AgentDockPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AgentDockPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPreferencesPersistAndRestoreAutomaticallySupportedValues() {
        let store = AgentDockPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.load(), .defaults)

        let expected = AgentDockPreferences(
            appearance: .dark,
            defaultView: .chats,
            refreshProfileActivity: false,
            refreshIntervalMinutes: 30,
            showStatusInProfileList: false
        )
        store.save(expected)
        XCTAssertEqual(store.load(), expected)

        store.restoreDefaults()
        XCTAssertEqual(store.load(), .defaults)
    }

    func testUnsupportedRefreshIntervalFallsBackToDefault() {
        let store = AgentDockPreferencesStore(defaults: defaults)
        var preferences = AgentDockPreferences.defaults
        preferences.refreshIntervalMinutes = 7
        store.save(preferences)

        XCTAssertEqual(
            store.load().refreshIntervalMinutes,
            AgentDockPreferences.defaults.refreshIntervalMinutes
        )
    }

    func testDefaultCodexConfigProfilePersistsAndCanReturnToBuiltIn() throws {
        let store = AgentDockPreferencesStore(defaults: defaults)
        var preferences = AgentDockPreferences.defaults
        preferences.defaultCodexConfigProfile = try CodexConfigProfile(validating: "ollama")

        store.save(preferences)
        XCTAssertEqual(store.load().defaultCodexConfigProfile?.name, "ollama")

        preferences.defaultCodexConfigProfile = nil
        store.save(preferences)
        XCTAssertNil(store.load().defaultCodexConfigProfile)
    }
}
