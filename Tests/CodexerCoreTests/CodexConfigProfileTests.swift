import XCTest
@testable import CodexerCore

final class CodexConfigProfileTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexConfigProfileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testProfileNamesMatchCodexCLIContract() throws {
        XCTAssertEqual(try CodexConfigProfile(validating: "ollama-local").name, "ollama-local")
        XCTAssertEqual(try CodexConfigProfile(validating: "work_2").name, "work_2")
        XCTAssertThrowsError(try CodexConfigProfile(validating: ""))
        XCTAssertThrowsError(try CodexConfigProfile(validating: "../unsafe"))
        XCTAssertThrowsError(try CodexConfigProfile(validating: "has spaces"))
    }

    func testDiscoveryFindsOnlySafeNamedConfigFiles() throws {
        try Data("model_provider = \"ollama\"\n".utf8)
            .write(to: root.appendingPathComponent("ollama.config.toml"))
        try Data("model = \"gpt-test\"\n".utf8)
            .write(to: root.appendingPathComponent("deep-review.config.toml"))
        try Data("model = \"base\"\n".utf8)
            .write(to: root.appendingPathComponent("config.toml"))
        try Data("ignored\n".utf8)
            .write(to: root.appendingPathComponent("notes.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.config.toml"),
            withDestinationURL: root.appendingPathComponent("ollama.config.toml")
        )

        XCTAssertEqual(
            CodexConfigProfile.discover(in: root).map(\.name),
            ["deep-review", "ollama"]
        )
    }

    func testSelectionRoundTripsThroughProfileMetadata() throws {
        let configProfile = try CodexConfigProfile(validating: "ollama")
        let profile = CodexProfile(
            name: "Local",
            slug: "local",
            rootDirectory: root,
            codexLaunchProfileSelection: .named(configProfile)
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(CodexProfile.self, from: data)

        XCTAssertEqual(decoded.codexLaunchProfileSelection, .named(configProfile))
    }

    func testProxyPrependsProfileBeforeDesktopAppServerArguments() throws {
        let configProfile = try CodexConfigProfile(validating: "ollama")
        let executableURL = URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex")

        XCTAssertEqual(
            CodexCLIProfileProxy.forwardedArguments(
                executableURL: executableURL,
                profile: configProfile,
                incomingArguments: ["app-server", "--analytics-default-enabled"]
            ),
            [
                executableURL.path,
                "--profile", "ollama",
                "app-server", "--analytics-default-enabled"
            ]
        )
    }
}
