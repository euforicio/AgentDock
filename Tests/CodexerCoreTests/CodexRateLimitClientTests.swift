import Foundation
import XCTest
@testable import CodexerCore

final class CodexRateLimitClientTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexRateLimitClientTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMissingProviderConfigurationUsesOpenAI() throws {
        XCTAssertEqual(
            try CodexProviderConfiguration.resolve(codexHomeURL: root),
            .openAI
        )
    }

    func testResolvesSelectedCustomProviderAndCompatibleRequestSettings() throws {
        try Data(#"""
        model_provider = "cursor_bridge"

        [model_providers.cursor_bridge]
        name = "Cursor Bridge"
        base_url = "http://127.0.0.1:32124/v1"
        wire_api = "responses"
        env_key = "SYNTHETIC_PROVIDER_TOKEN"
        http_headers = { "X-Client" = "AgentDock" }
        query_params = { region = "local" }

        [model_providers.cursor_bridge.env_http_headers]
        X-Workspace = "SYNTHETIC_WORKSPACE"
        """#.utf8).write(to: root.appendingPathComponent("config.toml"))

        let resolved = try CodexProviderConfiguration.resolve(codexHomeURL: root)
        guard case let .custom(provider) = resolved else {
            return XCTFail("Expected a custom provider")
        }
        XCTAssertEqual(provider.id, "cursor_bridge")
        XCTAssertEqual(provider.name, "Cursor Bridge")
        XCTAssertEqual(provider.environmentKey, "SYNTHETIC_PROVIDER_TOKEN")
        XCTAssertEqual(provider.directHeaders, ["X-Client": "AgentDock"])
        XCTAssertEqual(provider.environmentHeaders, ["X-Workspace": "SYNTHETIC_WORKSPACE"])
        XCTAssertEqual(provider.queryParameters, ["region": "local"])
        XCTAssertEqual(
            CustomProviderEndpoint.usageURL(
                provider,
                now: Date(timeIntervalSince1970: 1_000_000)
            )?.absoluteString,
            "http://127.0.0.1:32124/v1/organization/usage/completions?bucket_width=1d&end_time=1000000&limit=7&region=local&start_time=395200"
        )
    }

    func testSelectedProviderWithoutConfiguredBaseURLDoesNotUseOpenAIQuota() throws {
        try Data("model_provider = \"ollama\"\n".utf8)
            .write(to: root.appendingPathComponent("config.toml"))

        XCTAssertEqual(
            try CodexProviderConfiguration.resolve(codexHomeURL: root),
            .unsupported("ollama")
        )
    }

    func testCustomProviderUsageAllowsHTTPSAndLoopbackHTTPOnly() throws {
        XCTAssertNotNil(CustomProviderEndpoint.usageURL(provider("https://provider.example/v1")))
        XCTAssertNotNil(CustomProviderEndpoint.usageURL(provider("http://localhost:8080/v1")))
        XCTAssertNil(CustomProviderEndpoint.usageURL(provider("http://provider.example/v1")))
        XCTAssertNil(CustomProviderEndpoint.usageURL(provider("http://127.evil.example/v1")))
        XCTAssertNil(CustomProviderEndpoint.usageURL(provider("file:///tmp/provider/v1")))
        XCTAssertNil(CustomProviderEndpoint.usageURL(provider("https://user:secret@provider.example/v1")))
    }

    func testParsesOrganizationCompletionsUsage() throws {
        let data = Data(#"""
        {
          "object":"page",
          "data":[
            {
              "object":"bucket",
              "start_time":100,
              "end_time":200,
              "results":[
                {
                  "object":"organization.usage.completions.result",
                  "input_tokens":1000,
                  "output_tokens":200,
                  "input_cached_tokens":300,
                  "num_model_requests":4
                }
              ]
            },
            {
              "object":"bucket",
              "start_time":200,
              "end_time":300,
              "results":[
                {
                  "object":"organization.usage.completions.result",
                  "input_tokens":500,
                  "output_tokens":50,
                  "input_cached_tokens":100,
                  "num_model_requests":2
                }
              ]
            }
          ],
          "has_more":false,
          "next_page":null
        }
        """#.utf8)

        let limits = try CustomProviderUsageParser.parse(
            data,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(limits.apiUsage?.inputTokens, 1_500)
        XCTAssertEqual(limits.apiUsage?.outputTokens, 250)
        XCTAssertEqual(limits.apiUsage?.cachedInputTokens, 400)
        XCTAssertEqual(limits.apiUsage?.requestCount, 6)
        XCTAssertEqual(limits.apiUsage?.totalTokens, 1_750)
        XCTAssertEqual(limits.apiUsage?.startsAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(limits.apiUsage?.endsAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(limits.fetchedAt, Date(timeIntervalSince1970: 100))
    }

    private func provider(_ baseURL: String) -> CustomCodexProvider {
        CustomCodexProvider(
            id: "custom",
            name: "Custom",
            baseURL: URL(string: baseURL)!,
            environmentKey: nil,
            bearerToken: nil,
            directHeaders: [:],
            environmentHeaders: [:],
            queryParameters: [:]
        )
    }
}
