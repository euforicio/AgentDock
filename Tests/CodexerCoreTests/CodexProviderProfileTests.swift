import Foundation
import XCTest
@testable import CodexerCore

final class CodexProviderProfileTests: XCTestCase {
    func testProviderProfileValidatesExecutableAndName() throws {
        let executable = try makeExecutable()
        let profile = CodexProviderProfile(name: "Cursor Bridge", executableURL: executable)

        XCTAssertNoThrow(try profile.validate())
        XCTAssertEqual(profile.displayName, "Cursor Bridge")
        XCTAssertThrowsError(try CodexProviderProfile(name: "", executableURL: executable).validate())
        XCTAssertThrowsError(try CodexProviderProfile(
            name: "Missing",
            executableURL: executable.deletingLastPathComponent().appendingPathComponent("missing")
        ).validate())
    }

    func testLaunchEnvironmentSelectsProviderAndBuiltInPinsBundledExecutable() throws {
        let executable = try makeExecutable()
        let provider = CodexProviderProfile(name: "Bridge", executableURL: executable)
        let providerConfiguration = IsolatedCodexLaunchConfiguration(
            codexAppURL: URL(fileURLWithPath: "/Applications/Codex.app"),
            codexHomeURL: URL(fileURLWithPath: "/tmp/managed/CODEX_HOME"),
            electronUserDataURL: URL(fileURLWithPath: "/tmp/managed/ElectronUserData"),
            codexProviderProfile: provider
        )
        let inherited = [CodexProviderLaunch.cliPathEnvironmentKey: "/tmp/stale-cli"]

        let providerEnvironment = CodexProviderLaunch.launchEnvironment(
            base: inherited,
            configuration: providerConfiguration
        )
        XCTAssertEqual(providerEnvironment["CODEX_HOME"], "/tmp/managed/CODEX_HOME")
        XCTAssertEqual(providerEnvironment[CodexProviderLaunch.cliPathEnvironmentKey], executable.path)

        let builtInConfiguration = IsolatedCodexLaunchConfiguration(
            codexAppURL: URL(fileURLWithPath: "/Applications/Codex.app"),
            codexHomeURL: URL(fileURLWithPath: "/tmp/managed/CODEX_HOME"),
            electronUserDataURL: URL(fileURLWithPath: "/tmp/managed/ElectronUserData")
        )
        let builtInEnvironment = CodexProviderLaunch.launchEnvironment(
            base: inherited,
            configuration: builtInConfiguration
        )
        XCTAssertEqual(
            builtInEnvironment[CodexProviderLaunch.cliPathEnvironmentKey],
            "/Applications/Codex.app/Contents/Resources/codex"
        )
        XCTAssertEqual(builtInEnvironment["CODEX_HOME"], "/tmp/managed/CODEX_HOME")

        let stockEnvironment = CodexProviderLaunch.stockLaunchEnvironment(
            base: inherited.merging(["CODEX_HOME": "/tmp/managed"]) { _, latest in latest },
            codexAppURL: URL(fileURLWithPath: "/Applications/Codex.app")
        )
        XCTAssertEqual(
            stockEnvironment[CodexProviderLaunch.cliPathEnvironmentKey],
            "/Applications/Codex.app/Contents/Resources/codex"
        )
        XCTAssertNil(stockEnvironment["CODEX_HOME"])
    }

    private func makeExecutable() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexProviderProfileTests-\(UUID().uuidString)")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
