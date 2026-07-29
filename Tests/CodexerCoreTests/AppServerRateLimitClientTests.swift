import Darwin
import XCTest
@testable import CodexerCore

final class AppServerRateLimitClientTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexerAppServerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testUsesProfileCodexHomeAndAcceptsWhitespaceInResponseID() throws {
        let profile = CodexProfile(name: "Work", slug: "work", rootDirectory: root)
        try FileManager.default.createDirectory(at: profile.codexHomePath, withIntermediateDirectories: true)
        let initializeRequest = root.appendingPathComponent("initialize-request.json")
        let executable = try makeExecutable(named: "success", script: """
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *initialize*)
              if [ ! -f "\(initializeRequest.path)" ]; then
                printf '%s\n' "$line" > "\(initializeRequest.path)"
              fi
              printf '%s\n' '{"id":1,"result":{"userAgent":"test"}}'
              ;;
            *account/rateLimits/read*)
              if [ "$CODEX_HOME" = "\(profile.codexHomePath.path)" ]; then
                printf '%s\n' '{"id": 2, "result":{"rateLimits":{"limitId":"codex","planType":"pro"}}}'
              else
                printf '%s\n' '{"id": 2, "result":null}'
              fi
              exit 0
              ;;
          esac
        done
        """)
        let client = AppServerRateLimitClient(
            codexExecutable: executable,
            timeoutSeconds: 1,
            clientVersion: "0.1.0"
        )

        let limits = client.fetchRateLimits(
            for: profile,
            codexAppURL: URL(fileURLWithPath: "/Applications/Alternate Codex.app")
        )

        XCTAssertEqual(limits.planType, "pro")
        XCTAssertEqual(limits.buckets.map(\.id), ["codex"])
        XCTAssertNil(limits.errorMessage)
        let requestData = try Data(contentsOf: initializeRequest)
        let request = try XCTUnwrap(
            JSONSerialization.jsonObject(with: requestData) as? [String: Any]
        )
        let params = try XCTUnwrap(request["params"] as? [String: Any])
        let clientInfo = try XCTUnwrap(params["clientInfo"] as? [String: Any])
        XCTAssertEqual(clientInfo["version"] as? String, "0.1.0")
    }

    func testTimeoutTerminatesAndReturnsPromptly() throws {
        let profile = CodexProfile(name: "Slow", slug: "slow", rootDirectory: root)
        let executable = try makeExecutable(named: "timeout", script: """
        #!/bin/sh
        sleep 5
        """)
        let client = AppServerRateLimitClient(codexExecutable: executable, timeoutSeconds: 0.1)
        let start = Date()

        let limits = client.fetchRateLimits(for: profile, codexAppURL: URL(fileURLWithPath: "/Applications/Codex.app"))

        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertEqual(limits.errorMessage, "Timed out reading Codex usage limits.")
    }

    func testTaskCancellationTerminatesPromptly() async throws {
        let script = try makeExecutable(named: "cancel", script: """
        #!/bin/sh
        sleep 30
        """)
        let client = AppServerRateLimitClient(codexExecutable: script, timeoutSeconds: 10)
        let profile = CodexProfile(name: "Cancel", slug: "cancel", rootDirectory: root)
        let start = Date()

        let task = Task.detached {
            client.fetchRateLimits(for: profile, codexAppURL: URL(fileURLWithPath: "/unused"))
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.value

        XCTAssertEqual(result.errorMessage, "Usage-limit refresh was cancelled.")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testEarlyExitReturnsSpecificErrorWithoutWaitingForTimeout() throws {
        let profile = CodexProfile(name: "Exit", slug: "exit", rootDirectory: root)
        let executable = try makeExecutable(named: "exit", script: """
        #!/bin/sh
        exit 0
        """)
        let client = AppServerRateLimitClient(codexExecutable: executable, timeoutSeconds: 5)
        let start = Date()

        let limits = client.fetchRateLimits(for: profile, codexAppURL: URL(fileURLWithPath: "/Applications/Codex.app"))

        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        XCTAssertEqual(limits.errorMessage, "Codex app-server exited before returning usage limits.")
    }

    func testEarlyExitAlsoTerminatesBackgroundDescendants() throws {
        let profile = CodexProfile(name: "Child", slug: "child", rootDirectory: root)
        let childPIDFile = root.appendingPathComponent("child.pid")
        let executable = try makeExecutable(named: "background-child", script: """
        #!/bin/sh
        sleep 30 &
        child=$!
        printf '%s' "$child" > "\(childPIDFile.path)"
        exit 0
        """)
        let client = AppServerRateLimitClient(codexExecutable: executable, timeoutSeconds: 2)

        _ = client.fetchRateLimits(
            for: profile,
            codexAppURL: URL(fileURLWithPath: "/Applications/Codex.app")
        )

        let childPID = try XCTUnwrap(
            Int32(String(contentsOf: childPIDFile, encoding: .utf8))
        )
        let deadline = Date().addingTimeInterval(1)
        while processExists(childPID), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertFalse(processExists(childPID))
    }

    func testOversizedResponseIsBounded() throws {
        let profile = CodexProfile(name: "Large", slug: "large", rootDirectory: root)
        let executable = try makeExecutable(named: "large", script: """
        #!/bin/sh
        yes a | head -c 2048
        sleep 1
        """)
        let client = AppServerRateLimitClient(
            codexExecutable: executable,
            timeoutSeconds: 2,
            maximumResponseBytes: 128
        )

        let limits = client.fetchRateLimits(for: profile, codexAppURL: URL(fileURLWithPath: "/Applications/Codex.app"))

        XCTAssertEqual(limits.errorMessage, "Codex app-server response exceeded 128 bytes.")
    }

    func testBundledExecutableIsNotRunWhenAppValidationFails() {
        let profile = CodexProfile(name: "Rejected", slug: "rejected", rootDirectory: root)
        let client = AppServerRateLimitClient(appValidator: RejectingValidator())

        let limits = client.fetchRateLimits(
            for: profile,
            codexAppURL: URL(fileURLWithPath: "/tmp/TamperedCodex.app")
        )

        XCTAssertEqual(limits.errorMessage, "Rejected test app.")
    }

    private func makeExecutable(named name: String, script: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func processExists(_ processID: Int32) -> Bool {
        if kill(processID, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}

private struct RejectingValidator: CodexAppValidating {
    func validateCodexApp(at _: URL) throws {
        throw RejectedAppError()
    }
}

private struct RejectedAppError: LocalizedError {
    var errorDescription: String? { "Rejected test app." }
}
