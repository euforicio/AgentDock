import Foundation
import XCTest

final class ReleaseWorkflowTests: XCTestCase {
    func testReleaseWorkflowRunsOnlyForVersionTags() throws {
        let workflow = try String(contentsOf: repositoryRoot
            .appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)
        let triggerBlock = try XCTUnwrap(workflow.components(separatedBy: "\npermissions:").first)

        XCTAssertEqual(triggerBlock, """
        name: Build and Release

        on:
          push:
            tags:
              - "v*"

        """)
    }

    func testAppcastPublicationDependsOnReleaseAssetPublication() throws {
        let workflow = try String(contentsOf: repositoryRoot
            .appendingPathComponent(".github/workflows/release.yml"), encoding: .utf8)

        XCTAssertTrue(workflow.contains("  release:\n"))
        XCTAssertTrue(workflow.contains("  appcast:\n    name: Sign and publish stable appcast last\n    needs: release\n"))
        XCTAssertTrue(workflow.contains("https://github.com/euforicio/AgentDock/releases/download/$GITHUB_REF_NAME/"))
        XCTAssertTrue(workflow.contains("https://euforicio.github.io/AgentDock/appcast.xml"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
