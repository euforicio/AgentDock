import Foundation

public struct ProfileStats: Equatable, Sendable {
    public var totalSessions: Int
    public var weeklySessions: Int
    public var activeSessions: Int
    public var archivedSessions: Int
    public var totalTokens: Int
    public var weeklyTokens: Int
    public var averageTokensPerSession: Int
    public var peakSessionTokens: Int
    public var weeklyTokenBuckets: [TokenUsageBucket]
    public var weeklyWarnings: Int
    public var weeklyErrors: Int
    public var dataBytes: Int64
    public var lastActivityAt: Date?
    public var jobCounts: [String: Int]
    public var errorMessages: [String]

    public static let empty = ProfileStats(
        totalSessions: 0,
        weeklySessions: 0,
        activeSessions: 0,
        archivedSessions: 0,
        totalTokens: 0,
        weeklyTokens: 0,
        averageTokensPerSession: 0,
        peakSessionTokens: 0,
        weeklyTokenBuckets: [],
        weeklyWarnings: 0,
        weeklyErrors: 0,
        dataBytes: 0,
        lastActivityAt: nil,
        jobCounts: [:],
        errorMessages: []
    )
}

public struct TokenUsageBucket: Equatable, Identifiable, Sendable {
    public var id: Date { dayStart }
    public var dayStart: Date
    public var tokens: Int
    public var sessions: Int
}

public final class ProfileStatsScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let sqliteExecutable: URL
    private let queryTimeout: TimeInterval
    private let dataSizeCacheLock = NSLock()
    private var dataSizeCache: [String: (measuredAt: Date, bytes: Int64)] = [:]

    public init(
        fileManager: FileManager = .default,
        sqliteExecutable: URL = URL(fileURLWithPath: "/usr/bin/sqlite3"),
        queryTimeout: TimeInterval = 10
    ) {
        self.fileManager = fileManager
        self.sqliteExecutable = sqliteExecutable
        self.queryTimeout = queryTimeout
    }

    public func stats(for profile: CodexProfile, now: Date = Date()) -> ProfileStats {
        stats(
            codexHomeURL: profile.codexHomePath,
            dataRootURL: profile.profileDirectory,
            now: now
        )
    }

    public func stats(
        codexHomeURL: URL,
        dataRootURL: URL,
        now: Date = Date()
    ) -> ProfileStats {
        let weekStart = Int(now.timeIntervalSince1970) - (7 * 24 * 60 * 60)
        let stateDatabase = codexHomeURL.appendingPathComponent("state_5.sqlite")
        let logsDatabase = codexHomeURL.appendingPathComponent("logs_2.sqlite")

        var stats = ProfileStats.empty
        stats.dataBytes = cachedDirectorySize(dataRootURL, now: now)
        guard !Task.isCancelled else { return stats }

        if fileManager.fileExists(atPath: stateDatabase.path) {
            let stateRows = queryRows(
                database: stateDatabase,
                sql: """
                select
                  'summary',
                  count(*),
                  coalesce(sum(case when updated_at >= \(weekStart) then 1 else 0 end), 0),
                  coalesce(sum(case when archived = 0 then 1 else 0 end), 0),
                  coalesce(sum(case when archived != 0 then 1 else 0 end), 0),
                  coalesce(sum(tokens_used), 0),
                  coalesce(sum(case when updated_at >= \(weekStart) then tokens_used else 0 end), 0),
                  coalesce(max(tokens_used), 0),
                  coalesce(max(updated_at), 0)
                from threads;
                select
                  'bucket',
                  cast(updated_at / 86400 as integer) * 86400 as day_start,
                  sum(tokens_used),
                  count(*)
                from threads
                where updated_at >= \(weekStart) and tokens_used > 0
                group by day_start
                order by day_start;
                """,
                operation: "profile state",
                errors: &stats.errorMessages
            )
            if let sessionValues = stateRows.first(where: { $0.first == "summary" }),
               sessionValues.count >= 9
            {
                stats.totalSessions = int(sessionValues[1])
                stats.weeklySessions = int(sessionValues[2])
                stats.activeSessions = int(sessionValues[3])
                stats.archivedSessions = int(sessionValues[4])
                stats.totalTokens = int(sessionValues[5])
                stats.weeklyTokens = int(sessionValues[6])
                stats.peakSessionTokens = int(sessionValues[7])
                stats.averageTokensPerSession = stats.totalSessions == 0 ? 0 : stats.totalTokens / stats.totalSessions
                let lastUpdated = int(sessionValues[8])
                if lastUpdated > 0 {
                    stats.lastActivityAt = Date(timeIntervalSince1970: TimeInterval(lastUpdated))
                }
            }

            guard !Task.isCancelled else { return stats }
            stats.weeklyTokenBuckets = stateRows.compactMap { row in
                guard row.first == "bucket", row.count >= 4 else { return nil }
                return TokenUsageBucket(
                    dayStart: Date(timeIntervalSince1970: TimeInterval(int(row[1]))),
                    tokens: int(row[2]),
                    sessions: int(row[3])
                )
            }
            stats.jobCounts = stateRows.reduce(into: [:]) { result, row in
                guard row.first == "job", row.count >= 3, !row[1].isEmpty else {
                    return
                }
                result[row[1]] = int(row[2])
            }

            var schemaErrors: [String] = []
            let hasAgentJobs = querySingleRow(
                database: stateDatabase,
                sql: "select count(*) from sqlite_schema where type = 'table' and name = 'agent_jobs';",
                operation: "profile schema",
                errors: &schemaErrors
            ).first == "1"
            if hasAgentJobs {
                let jobRows = queryRows(
                    database: stateDatabase,
                    sql: "select 'job', status, count(*) from agent_jobs group by status;",
                    operation: "job summary",
                    errors: &stats.errorMessages
                )
                stats.jobCounts = jobRows.reduce(into: [:]) { result, row in
                    guard row.first == "job", row.count >= 3, !row[1].isEmpty else {
                        return
                    }
                    result[row[1]] = int(row[2])
                }
            }
        }

        guard !Task.isCancelled else { return stats }
        if fileManager.fileExists(atPath: logsDatabase.path) {
            let logValues = querySingleRow(
                database: logsDatabase,
                sql: """
                select
                  coalesce(sum(case when upper(level) in ('WARN', 'WARNING') then 1 else 0 end), 0),
                  coalesce(sum(case when upper(level) = 'ERROR' then 1 else 0 end), 0),
                  (select coalesce(max(ts), 0) from logs)
                from logs
                where ts >= \(weekStart);
                """,
                operation: "log summary",
                errors: &stats.errorMessages
            )
            if logValues.count >= 3 {
                stats.weeklyWarnings = int(logValues[0])
                stats.weeklyErrors = int(logValues[1])
                let lastLog = int(logValues[2])
                if lastLog > 0 {
                    let logDate = Date(timeIntervalSince1970: TimeInterval(lastLog))
                    if stats.lastActivityAt == nil || logDate > (stats.lastActivityAt ?? .distantPast) {
                        stats.lastActivityAt = logDate
                    }
                }
            }
        }

        return stats
    }

    private func querySingleRow(
        database: URL,
        sql: String,
        operation: String,
        errors: inout [String]
    ) -> [String] {
        queryRows(database: database, sql: sql, operation: operation, errors: &errors).first ?? []
    }

    private func queryRows(
        database: URL,
        sql: String,
        operation: String,
        errors: inout [String]
    ) -> [[String]] {
        let process = Process()
        process.executableURL = sqliteExecutable
        process.arguments = [
            "-readonly",
            "-noheader",
            "-separator",
            "\u{1F}",
            SQLiteReadOnly.databaseArgument(for: database, fileManager: fileManager),
            sql
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let capture = StatsProcessCapture(maximumBytes: 8 * 1_024 * 1_024)
        let completion = DispatchSemaphore(value: 0)
        output.fileHandleForReading.readabilityHandler = { handle in
            capture.append(handle.availableData)
        }
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(queryTimeout)
            var completed = false
            while !Task.isCancelled, Date() < deadline {
                if completion.wait(timeout: .now() + 0.1) == .success {
                    completed = true
                    break
                }
            }
            guard !Task.isCancelled else {
                output.fileHandleForReading.readabilityHandler = nil
                SubprocessTerminator.terminateAndWait(process)
                return []
            }
            guard completed else {
                output.fileHandleForReading.readabilityHandler = nil
                SubprocessTerminator.terminateAndWait(process)
                errors.append("Timed out reading \(operation).")
                return []
            }
            output.fileHandleForReading.readabilityHandler = nil
            capture.append(output.fileHandleForReading.readDataToEndOfFile())
            process.waitUntilExit()
            if capture.exceededLimit {
                errors.append("Could not read \(operation): sqlite3 output exceeded the safety limit.")
                return []
            }
            guard process.terminationStatus == 0 else {
                errors.append("Could not read \(operation) (sqlite3 exited with status \(process.terminationStatus)).")
                return []
            }
            let data = capture.data
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return []
            }
            return text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { line in
                    line.split(separator: "\u{1F}", omittingEmptySubsequences: false)
                        .map(String.init)
                }
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            SubprocessTerminator.terminateAndWait(process)
            errors.append("Could not read \(operation): \(error.localizedDescription)")
            return []
        }
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: []
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard !Task.isCancelled else { return total }
            guard
                let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                values.isRegularFile == true
            else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func cachedDirectorySize(_ url: URL, now: Date) -> Int64 {
        let key = url.standardizedFileURL.path
        if let cached = dataSizeCacheLock.withLock({ dataSizeCache[key] }),
           now.timeIntervalSince(cached.measuredAt) < 60
        {
            return cached.bytes
        }
        let bytes = directorySize(url)
        dataSizeCacheLock.withLock {
            dataSizeCache[key] = (now, bytes)
        }
        return bytes
    }

    private func int(_ value: String) -> Int {
        Int(value) ?? 0
    }

}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}

private final class StatsProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private var storage = Data()
    private var overflowed = false

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var exceededLimit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return overflowed
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !overflowed else { return }
        guard storage.count + data.count <= maximumBytes else {
            overflowed = true
            storage.removeAll(keepingCapacity: false)
            return
        }
        storage.append(data)
    }
}
