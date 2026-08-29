import XCTest
@testable import CodexerCore

final class ProductAnalyticsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ProductAnalyticsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAnalyticsDefaultsToGrantedAndCreatesIdentifier() {
        let store = AnalyticsConsentStore(defaults: defaults)
        XCTAssertEqual(store.consent, .undecided)
        XCTAssertNil(store.installationID)

        _ = ProductAnalytics(consentStore: store, configuration: nil)

        XCTAssertEqual(store.consent, .granted)
        XCTAssertNotNil(store.installationID)
        XCTAssertEqual(defaults.string(forKey: "AgentDock.analyticsConsent.v1"), "granted")
        XCTAssertNotNil(defaults.string(forKey: "AgentDock.analyticsInstallationID.v1"))
    }

    func testExplicitOptOutSurvivesDefaultEnablement() {
        let store = AnalyticsConsentStore(defaults: defaults)
        store.denyAndDeleteIdentifier()

        _ = ProductAnalytics(consentStore: store, configuration: nil)

        XCTAssertEqual(store.consent, .denied)
        XCTAssertNil(store.installationID)
    }

    func testInvalidPersistedConsentFailsClosed() {
        defaults.set("unexpected", forKey: "AgentDock.analyticsConsent.v1")
        let store = AnalyticsConsentStore(defaults: defaults)

        _ = ProductAnalytics(consentStore: store, configuration: nil)

        XCTAssertEqual(store.consent, .denied)
        XCTAssertNil(store.installationID)
    }

    func testGrantPersistsStableIdentifierAndOptOutDeletesIt() {
        let store = AnalyticsConsentStore(defaults: defaults)
        let first = store.grant()
        XCTAssertEqual(store.consent, .granted)
        XCTAssertEqual(store.installationID, first)
        XCTAssertEqual(store.grant(), first)

        store.denyAndDeleteIdentifier()
        XCTAssertEqual(store.consent, .denied)
        XCTAssertNil(store.installationID)

        let replacement = store.grant()
        XCTAssertNotEqual(replacement, first)
    }

    func testResetReturnsToUndecidedAndDeletesIdentifier() {
        let store = AnalyticsConsentStore(defaults: defaults)
        _ = store.grant()
        store.resetDecisionAndDeleteIdentifier()
        XCTAssertEqual(store.consent, .undecided)
        XCTAssertNil(store.installationID)
    }

    func testEventSchemaRejectsMissingDuplicateAndDisallowedProperties() throws {
        XCTAssertNil(AnalyticsEvent(.navigation, [.surface(.overview)]))
        XCTAssertNil(AnalyticsEvent(.navigation, [.action(.viewed), .action(.selected)]))
        XCTAssertNil(AnalyticsEvent(.navigation, [.action(.viewed), .errorCode(.unknownSafe)]))
        XCTAssertNotNil(AnalyticsEvent(.navigation, [.action(.viewed), .surface(.overview)]))
    }

    func testPayloadIsConsentGatedAndContainsOnlyAllowlistedContext() throws {
        let store = AnalyticsConsentStore(defaults: defaults)
        store.denyAndDeleteIdentifier()
        let configuration = try XCTUnwrap(ProductAnalyticsConfiguration(
            projectToken: "phc_synthetic_public_token_123456",
            host: "https://eu.i.posthog.com"
        ))
        let analytics = ProductAnalytics(
            consentStore: store,
            configuration: configuration,
            appVersion: "1.2.3-local+/Users/person",
            osMajorVersion: 26,
            architecture: "arm64"
        )
        let event = try XCTUnwrap(AnalyticsEvent(
            .profileLifecycle,
            [.action(.created), .provider(.codex), .outcome(.succeeded), .countBucket(.one)]
        ))
        XCTAssertNil(analytics.payload(for: event))

        let identifier = store.grant()
        let payload = try XCTUnwrap(analytics.payload(for: event))
        XCTAssertEqual(payload["event"] as? String, "profile_lifecycle")
        let properties = try XCTUnwrap(payload["properties"] as? [String: Any])
        XCTAssertEqual(properties["distinct_id"] as? String, identifier.uuidString.lowercased())
        XCTAssertEqual(properties["$geoip_disable"] as? Bool, true)
        XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
        XCTAssertEqual(properties["app_version"] as? String, "1.2.3-")
        XCTAssertEqual(properties["provider"] as? String, "codex")
        XCTAssertNil(properties["name"])
        XCTAssertNil(properties["path"])
        XCTAssertNil(properties["prompt"])
        XCTAssertNil(properties["session_id"])
        XCTAssertLessThanOrEqual(properties.count, 16)

        store.denyAndDeleteIdentifier()
        XCTAssertNil(analytics.payload(for: event))
    }

    func testConfigurationRequiresPublicTokenAndSecureBoundedHost() {
        XCTAssertNil(ProductAnalyticsConfiguration(projectToken: "secret", host: "https://us.i.posthog.com"))
        XCTAssertNil(ProductAnalyticsConfiguration(projectToken: "phc_validtoken123", host: "http://us.i.posthog.com"))
        XCTAssertNil(ProductAnalyticsConfiguration(projectToken: "phc_validtoken123", host: "https://user@example.com"))
        XCTAssertNil(ProductAnalyticsConfiguration(projectToken: "phc_validtoken123", host: "https://example.com:8443"))
        XCTAssertNil(ProductAnalyticsConfiguration(projectToken: "phc_validtoken123", host: "https://example.com/private"))
        XCTAssertNil(ProductAnalyticsConfiguration(projectToken: "phc_validtoken123", host: "https://example.com?path=private"))
        XCTAssertEqual(
            ProductAnalyticsConfiguration(projectToken: "phc_validtoken123", host: "https://us.i.posthog.com")?.host.absoluteString,
            "https://us.i.posthog.com/batch/"
        )
    }

    func testBucketsAreBounded() {
        XCTAssertEqual(AnalyticsCountBucket(-1), .zero)
        XCTAssertEqual(AnalyticsCountBucket(4), .twoToFive)
        XCTAssertEqual(AnalyticsCountBucket(1_000_000), .twentyOnePlus)
        XCTAssertEqual(AnalyticsDurationBucket(milliseconds: -1), .under100ms)
        XCTAssertEqual(AnalyticsDurationBucket(milliseconds: 9_999), .seconds2To9)
        XCTAssertEqual(AnalyticsDurationBucket(milliseconds: 50_000), .seconds10Plus)
    }

    func testCaptureBatchesInMemoryAndOptOutPurgesBeforeDelivery() throws {
        let store = AnalyticsConsentStore(defaults: defaults)
        _ = store.grant()
        let analytics = ProductAnalytics(
            consentStore: store,
            configuration: try XCTUnwrap(ProductAnalyticsConfiguration(
                projectToken: "phc_synthetic_public_token_123456",
                host: "https://eu.i.posthog.com"
            ))
        )
        let event = try XCTUnwrap(AnalyticsEvent(
            .featureAdoption,
            [.action(.viewed), .feature(.chats), .surface(.chats)]
        ))
        analytics.capture(event)
        analytics.capture(event)
        XCTAssertEqual(analytics.deliverySnapshot().pending, 2)
        XCTAssertEqual(analytics.deliverySnapshot().active, 0)

        analytics.denyConsent()
        XCTAssertEqual(analytics.deliverySnapshot().pending, 0)
        XCTAssertEqual(analytics.deliverySnapshot().active, 0)
        XCTAssertNil(store.installationID)
    }
}
