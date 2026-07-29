import XCTest
@testable import CodexerCore

final class ProfileStatsScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexerStatsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMissingDatabasesReturnEmptyStatsWithDataSize() throws {
        let profile = CodexProfile(name: "Empty", slug: "empty", rootDirectory: root)
        try FileManager.default.createDirectory(at: profile.codexHomePath, withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: profile.codexHomePath.appendingPathComponent("sample.txt"))

        let stats = ProfileStatsScanner().stats(for: profile, now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(stats.totalSessions, 0)
        XCTAssertEqual(stats.weeklySessions, 0)
        XCTAssertEqual(stats.averageTokensPerSession, 0)
        XCTAssertEqual(stats.peakSessionTokens, 0)
        XCTAssertTrue(stats.weeklyTokenBuckets.isEmpty)
        XCTAssertEqual(stats.dataBytes, 3)
        XCTAssertNil(stats.lastActivityAt)
        XCTAssertTrue(stats.errorMessages.isEmpty)
    }

    func testStatsSummarizeSessionsTokensJobsAndWeeklyLogs() throws {
        let profile = CodexProfile(name: "Work", slug: "work", rootDirectory: root)
        try FileManager.default.createDirectory(at: profile.codexHomePath, withIntermediateDirectories: true)
        let state = profile.codexHomePath.appendingPathComponent("state_5.sqlite")
        let logs = profile.codexHomePath.appendingPathComponent("logs_2.sqlite")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = Int(now.timeIntervalSince1970) - 60
        let yesterday = Int(now.timeIntervalSince1970) - (24 * 60 * 60)
        let old = Int(now.timeIntervalSince1970) - (9 * 24 * 60 * 60)

        try runSQLite(state, sql: """
        create table threads (
          id text primary key,
          created_at integer not null,
          updated_at integer not null,
          tokens_used integer not null default 0,
          archived integer not null default 0
        );
        create table agent_jobs (
          id text primary key,
          status text not null
        );
        insert into threads values ('recent', \(recent), \(recent), 1200, 0);
        insert into threads values ('yesterday', \(yesterday), \(yesterday), 600, 0);
        insert into threads values ('old', \(old), \(old), 300, 1);
        insert into agent_jobs values ('job-1', 'running');
        insert into agent_jobs values ('job-2', 'completed');
        """)
        try runSQLite(logs, sql: """
        create table logs (
          id integer primary key autoincrement,
          ts integer not null,
          level text not null,
          estimated_bytes integer not null default 0
        );
        insert into logs (ts, level, estimated_bytes) values (\(recent), 'WARN', 10);
        insert into logs (ts, level, estimated_bytes) values (\(recent), 'ERROR', 20);
        insert into logs (ts, level, estimated_bytes) values (\(old), 'ERROR', 40);
        """)

        let stats = ProfileStatsScanner().stats(for: profile, now: now)

        XCTAssertEqual(stats.totalSessions, 3)
        XCTAssertEqual(stats.weeklySessions, 2)
        XCTAssertEqual(stats.activeSessions, 2)
        XCTAssertEqual(stats.archivedSessions, 1)
        XCTAssertEqual(stats.totalTokens, 2100)
        XCTAssertEqual(stats.weeklyTokens, 1800)
        XCTAssertEqual(stats.averageTokensPerSession, 700)
        XCTAssertEqual(stats.peakSessionTokens, 1200)
        XCTAssertEqual(stats.weeklyTokenBuckets.reduce(0) { $0 + $1.tokens }, 1800)
        XCTAssertEqual(stats.weeklyTokenBuckets.reduce(0) { $0 + $1.sessions }, 2)
        XCTAssertEqual(stats.weeklyTokenBuckets.count, 2)
        XCTAssertEqual(stats.jobCounts["running"], 1)
        XCTAssertEqual(stats.jobCounts["completed"], 1)
        XCTAssertEqual(stats.weeklyWarnings, 1)
        XCTAssertEqual(stats.weeklyErrors, 1)
        XCTAssertEqual(stats.lastActivityAt, Date(timeIntervalSince1970: TimeInterval(recent)))
        XCTAssertTrue(stats.errorMessages.isEmpty)
    }

    func testMalformedSchemaReportsAnActionableError() throws {
        let profile = CodexProfile(name: "Broken", slug: "broken", rootDirectory: root)
        try FileManager.default.createDirectory(at: profile.codexHomePath, withIntermediateDirectories: true)
        let state = profile.codexHomePath.appendingPathComponent("state_5.sqlite")
        try runSQLite(state, sql: "create table unrelated (id text);")

        let stats = ProfileStatsScanner().stats(for: profile)

        XCTAssertFalse(stats.errorMessages.isEmpty)
        XCTAssertTrue(stats.errorMessages.contains { $0.contains("profile state") })
    }

    func testMissingOptionalAgentJobsTableDoesNotBreakThreadStats() throws {
        let profile = CodexProfile(name: "Enterprise", slug: "enterprise", rootDirectory: root)
        try FileManager.default.createDirectory(at: profile.codexHomePath, withIntermediateDirectories: true)
        let state = profile.codexHomePath.appendingPathComponent("state_5.sqlite")
        let now = Int(Date().timeIntervalSince1970)
        try runSQLite(state, sql: """
        create table threads (
          id text primary key,
          updated_at integer not null,
          tokens_used integer not null default 0,
          archived integer not null default 0
        );
        insert into threads values ('business-thread', \(now), 800, 0);
        """)

        let stats = ProfileStatsScanner().stats(for: profile)

        XCTAssertEqual(stats.totalSessions, 1)
        XCTAssertEqual(stats.totalTokens, 800)
        XCTAssertTrue(stats.jobCounts.isEmpty)
        XCTAssertTrue(stats.errorMessages.isEmpty)
    }

    func testClosedWALDatabasesRemainReadableWithoutSidecarFiles() throws {
        let profile = CodexProfile(name: "Closed", slug: "closed", rootDirectory: root)
        try FileManager.default.createDirectory(at: profile.codexHomePath, withIntermediateDirectories: true)
        let state = profile.codexHomePath.appendingPathComponent("state_5.sqlite")
        let logs = profile.codexHomePath.appendingPathComponent("logs_2.sqlite")
        let now = Int(Date().timeIntervalSince1970)

        try runSQLite(state, sql: """
        pragma journal_mode = WAL;
        create table threads (
          id text primary key,
          updated_at integer not null,
          tokens_used integer not null default 0,
          archived integer not null default 0
        );
        insert into threads values ('closed-thread', \(now), 1200, 0);
        """)
        try runSQLite(logs, sql: """
        pragma journal_mode = WAL;
        create table logs (
          id integer primary key autoincrement,
          ts integer not null,
          level text not null,
          estimated_bytes integer not null default 0
        );
        insert into logs (ts, level) values (\(now), 'ERROR');
        """)
        try? FileManager.default.removeItem(atPath: state.path + "-wal")
        try? FileManager.default.removeItem(atPath: state.path + "-shm")
        try? FileManager.default.removeItem(atPath: logs.path + "-wal")
        try? FileManager.default.removeItem(atPath: logs.path + "-shm")
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.path + "-shm"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logs.path + "-shm"))

        let stats = ProfileStatsScanner().stats(for: profile)

        XCTAssertEqual(stats.totalSessions, 1)
        XCTAssertEqual(stats.totalTokens, 1200)
        XCTAssertEqual(stats.weeklyErrors, 1)
        XCTAssertTrue(stats.errorMessages.isEmpty)
    }

    func testLargeWeeklyHistoryCompletesWithoutPipeDeadlock() throws {
        let profile = CodexProfile(name: "Large", slug: "large", rootDirectory: root)
        try FileManager.default.createDirectory(at: profile.codexHomePath, withIntermediateDirectories: true)
        let state = profile.codexHomePath.appendingPathComponent("state_5.sqlite")
        let now = Int(Date().timeIntervalSince1970)
        try runSQLite(state, sql: """
        create table threads (
          id text primary key,
          created_at integer not null,
          updated_at integer not null,
          tokens_used integer not null default 0,
          archived integer not null default 0
        );
        create table agent_jobs (id text primary key, status text not null);
        with recursive sequence(value) as (
          select 1 union all select value + 1 from sequence where value < 10000
        )
        insert into threads
        select printf('thread-%d', value), \(now), \(now) - (value % 86400), value, 0 from sequence;
        """)
        let start = Date()

        let stats = ProfileStatsScanner().stats(for: profile)

        XCTAssertEqual(stats.totalSessions, 10_000)
        XCTAssertFalse(stats.weeklyTokenBuckets.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertTrue(stats.errorMessages.isEmpty)
    }

    func testHungSQLiteProcessIsTerminatedAtTimeout() throws {
        let profile = CodexProfile(name: "Hung", slug: "hung", rootDirectory: root)
        try FileManager.default.createDirectory(at: profile.codexHomePath, withIntermediateDirectories: true)
        try Data().write(to: profile.codexHomePath.appendingPathComponent("state_5.sqlite"))
        let fakeSQLite = root.appendingPathComponent("slow-sqlite")
        try Data("#!/bin/sh\nsleep 5\n".utf8).write(to: fakeSQLite)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSQLite.path)
        let scanner = ProfileStatsScanner(sqliteExecutable: fakeSQLite, queryTimeout: 0.1)
        let start = Date()

        let stats = scanner.stats(for: profile)

        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertTrue(stats.errorMessages.contains { $0.contains("Timed out") })
    }

    private func runSQLite(_ database: URL, sql: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
