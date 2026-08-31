import XCTest
@testable import CodexerCore

final class SQLiteReadOnlyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteReadOnlyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    func testRegularDatabaseUsesImmutableURIWithoutSidecars() throws {
        let database = root.appendingPathComponent("state.sqlite")
        try Data("synthetic sqlite bytes".utf8).write(to: database)
        let canonicalDatabase = canonical(database)

        XCTAssertEqual(
            try SQLiteReadOnly.databaseArgument(for: database),
            canonicalDatabase.absoluteString + "?immutable=1"
        )
    }

    func testRegularSidecarDisablesImmutableMode() throws {
        let database = root.appendingPathComponent("state.sqlite")
        try Data("synthetic sqlite bytes".utf8).write(to: database)
        try Data().write(to: URL(fileURLWithPath: database.path + "-wal"))

        XCTAssertEqual(try SQLiteReadOnly.databaseArgument(for: database), canonical(database).path)
    }

    func testRejectsSymlinkedDatabaseAndSidecars() throws {
        let outside = root.appendingPathComponent("outside.sqlite")
        try Data("synthetic sqlite bytes".utf8).write(to: outside)

        let linkedDatabase = root.appendingPathComponent("linked.sqlite")
        try FileManager.default.createSymbolicLink(at: linkedDatabase, withDestinationURL: outside)
        XCTAssertThrowsError(try SQLiteReadOnly.databaseArgument(for: linkedDatabase))

        let database = root.appendingPathComponent("state.sqlite")
        try Data("synthetic sqlite bytes".utf8).write(to: database)
        let linkedWAL = URL(fileURLWithPath: database.path + "-wal")
        try FileManager.default.createSymbolicLink(at: linkedWAL, withDestinationURL: outside)
        XCTAssertThrowsError(try SQLiteReadOnly.databaseArgument(for: database))
    }

    private func canonical(_ database: URL) -> URL {
        let parent = database.deletingLastPathComponent()
        let resolved = realpath(parent.path, nil)!
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
            .appendingPathComponent(database.lastPathComponent)
    }
}
