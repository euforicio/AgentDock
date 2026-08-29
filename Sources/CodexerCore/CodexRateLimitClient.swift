import Darwin
import Foundation

public final class CodexRateLimitClient: @unchecked Sendable {
    private let nativeClient: AppServerRateLimitClient
    private let customClient: CustomProviderRateLimitClient
    private let fileManager: FileManager

    public init(
        nativeClient: AppServerRateLimitClient = AppServerRateLimitClient(),
        fileManager: FileManager = .default
    ) {
        self.nativeClient = nativeClient
        customClient = CustomProviderRateLimitClient()
        self.fileManager = fileManager
    }

    public func fetchRateLimits(
        for profile: CodexProfile,
        codexAppURL: URL
    ) async -> ProfileRateLimits {
        await fetchRateLimits(codexHomeURL: profile.codexHomePath, codexAppURL: codexAppURL)
    }

    public func fetchRateLimits(
        codexHomeURL: URL,
        codexAppURL: URL
    ) async -> ProfileRateLimits {
        do {
            switch try CodexProviderConfiguration.resolve(
                codexHomeURL: codexHomeURL,
                fileManager: fileManager
            ) {
            case .openAI:
                return nativeClient.fetchRateLimits(
                    codexHomeURL: codexHomeURL,
                    codexAppURL: codexAppURL
                )
            case let .custom(provider):
                return await customClient.fetchRateLimits(provider: provider)
            case let .unsupported(providerID):
                return ProfileRateLimits(
                    errorMessage: "Usage limits are unavailable for the \(providerID) provider."
                )
            }
        } catch {
            return ProfileRateLimits(
                errorMessage: "The active Codex provider configuration could not be read safely."
            )
        }
    }
}

enum CodexProviderConfiguration: Equatable, Sendable {
    case openAI
    case custom(CustomCodexProvider)
    case unsupported(String)

    private static let maximumConfigBytes = 1_048_576

    static func resolve(
        codexHomeURL: URL,
        fileManager: FileManager = .default
    ) throws -> Self {
        let configURL = codexHomeURL.appendingPathComponent("config.toml")
        guard fileManager.fileExists(atPath: configURL.path) else { return .openAI }
        let content = try readBoundedConfig(at: configURL)
        let document = NarrowTOMLDocument(content)
        let providerID = document.topLevelString("model_provider") ?? "openai"
        guard providerID != "openai" else { return .openAI }
        guard let baseURLString = document.string(
            "base_url",
            in: ["model_providers", providerID]
        ), let baseURL = URL(string: baseURLString) else {
            return .unsupported(providerID)
        }

        let providerTable = ["model_providers", providerID]
        let directHeaders = document.stringMap(
            "http_headers",
            in: providerTable
        )
        let environmentHeaders = document.stringMap(
            "env_http_headers",
            in: providerTable
        )
        let queryParameters = document.stringMap(
            "query_params",
            in: providerTable
        )
        return .custom(CustomCodexProvider(
            id: providerID,
            name: document.string("name", in: ["model_providers", providerID])
                ?? providerID,
            baseURL: baseURL,
            environmentKey: document.string(
                "env_key",
                in: ["model_providers", providerID]
            ),
            bearerToken: document.string(
                "experimental_bearer_token",
                in: ["model_providers", providerID]
            ),
            directHeaders: directHeaders,
            environmentHeaders: environmentHeaders,
            queryParameters: queryParameters
        ))
    }

    private static func readBoundedConfig(at url: URL) throws -> String {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize <= maximumConfigBytes
        else {
            throw CodexProviderConfigurationError.unsafeConfig
        }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CodexProviderConfigurationError.unsafeConfig }
        defer { Darwin.close(descriptor) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else { throw CodexProviderConfigurationError.unsafeConfig }
            if count == 0 { break }
            guard data.count + count <= maximumConfigBytes else {
                throw CodexProviderConfigurationError.unsafeConfig
            }
            data.append(buffer, count: count)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw CodexProviderConfigurationError.invalidEncoding
        }
        return content
    }
}

struct CustomCodexProvider: Equatable, Sendable {
    var id: String
    var name: String
    var baseURL: URL
    var environmentKey: String?
    var bearerToken: String?
    var directHeaders: [String: String]
    var environmentHeaders: [String: String]
    var queryParameters: [String: String]
}

private enum CodexProviderConfigurationError: Error {
    case unsafeConfig
    case invalidEncoding
}

private struct NarrowTOMLDocument {
    private var values: [[String]: [String: String]] = [:]

    init(_ content: String) {
        var table: [String] = []
        var multilineDelimiter: String?
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let delimiter = multilineDelimiter {
                if Self.delimiterCount(in: line, delimiter: delimiter).isMultiple(of: 2) == false {
                    multilineDelimiter = nil
                }
                continue
            }
            if let delimiter = Self.startingMultilineDelimiter(in: line) {
                multilineDelimiter = delimiter
                continue
            }
            let stripped = Self.stripComment(line).trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { continue }
            if let parsedTable = Self.tablePath(stripped) {
                table = parsedTable
                continue
            }
            guard let (key, value) = Self.assignment(stripped) else { continue }
            values[table, default: [:]][key] = value
        }
    }

    func topLevelString(_ key: String) -> String? {
        Self.stringValue(values[[]]?[key])
    }

    func string(_ key: String, in table: [String]) -> String? {
        Self.stringValue(values[table]?[key])
    }

    func stringMap(_ key: String, in table: [String]) -> [String: String] {
        var result: [String: String] = (values[table + [key]] ?? [:]).reduce(
            into: [String: String]()
        ) { result, entry in
            if let value = Self.stringValue(entry.value) {
                result[entry.key] = value
            }
        }
        if let inline = values[table]?[key] {
            result.merge(Self.inlineStringMap(inline)) { _, inlineValue in inlineValue }
        }
        return result
    }

    private static func assignment(_ line: String) -> (String, String)? {
        var quote: Character?
        var escaped = false
        for index in line.indices {
            let character = line[index]
            if escaped {
                escaped = false
                continue
            }
            if character == "\\", quote == "\"" {
                escaped = true
                continue
            }
            if character == "\"" || character == "'" {
                quote = quote == nil ? character : (quote == character ? nil : quote)
                continue
            }
            if character == "=", quote == nil {
                let key = line[..<index].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, !value.isEmpty else { return nil }
                return (unquotedKey(String(key)), String(value))
            }
        }
        return nil
    }

    private static func tablePath(_ line: String) -> [String]? {
        guard line.first == "[", line.last == "]", !line.hasPrefix("[[") else { return nil }
        let body = line.dropFirst().dropLast()
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in body {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\", quote == "\"" {
                current.append(character)
                escaped = true
                continue
            }
            if character == "\"" || character == "'" {
                current.append(character)
                quote = quote == nil ? character : (quote == character ? nil : quote)
                continue
            }
            if character == ".", quote == nil {
                result.append(unquotedKey(current.trimmingCharacters(in: .whitespaces)))
                current = ""
            } else {
                current.append(character)
            }
        }
        guard quote == nil else { return nil }
        result.append(unquotedKey(current.trimmingCharacters(in: .whitespaces)))
        return result.allSatisfy { !$0.isEmpty } ? result : nil
    }

    private static func stringValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        if raw.hasPrefix("\"") && raw.hasSuffix("\"") {
            return try? JSONDecoder().decode(String.self, from: Data(raw.utf8))
        }
        if raw.hasPrefix("'") && raw.hasSuffix("'") {
            return String(raw.dropFirst().dropLast())
        }
        return nil
    }

    private static func inlineStringMap(_ raw: String) -> [String: String] {
        guard raw.first == "{", raw.last == "}" else { return [:] }
        let body = raw.dropFirst().dropLast()
        var entries: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in body {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\", quote == "\"" {
                current.append(character)
                escaped = true
                continue
            }
            if character == "\"" || character == "'" {
                current.append(character)
                quote = quote == nil ? character : (quote == character ? nil : quote)
                continue
            }
            if character == ",", quote == nil {
                entries.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        entries.append(current)
        return entries.reduce(into: [:]) { result, entry in
            guard let (key, value) = assignment(entry) else { return }
            if let parsed = stringValue(value) {
                result[key] = parsed
            }
        }
    }

    private static func unquotedKey(_ key: String) -> String {
        stringValue(key) ?? key
    }

    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var escaped = false
        for index in line.indices {
            let character = line[index]
            if escaped {
                escaped = false
                continue
            }
            if character == "\\", quote == "\"" {
                escaped = true
                continue
            }
            if character == "\"" || character == "'" {
                quote = quote == nil ? character : (quote == character ? nil : quote)
            } else if character == "#", quote == nil {
                return String(line[..<index])
            }
        }
        return line
    }

    private static func startingMultilineDelimiter(in line: String) -> String? {
        for delimiter in ["\"\"\"", "'''"]
        where delimiterCount(in: line, delimiter: delimiter).isMultiple(of: 2) == false {
            return delimiter
        }
        return nil
    }

    private static func delimiterCount(in value: String, delimiter: String) -> Int {
        value.components(separatedBy: delimiter).count - 1
    }
}

private final class CustomProviderRateLimitClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let timeoutSeconds: TimeInterval = 8
    private let maximumResponseBytes = 1_048_576
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func fetchRateLimits(provider: CustomCodexProvider) async -> ProfileRateLimits {
        guard let usageURL = Self.usageURL(provider) else {
            return failure(provider, "The provider usage URL is not safe.")
        }
        var request = URLRequest(url: usageURL)
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyHeaders(provider, to: &request)

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                return failure(provider, "The provider returned an invalid response.")
            }
            guard (200..<300).contains(response.statusCode) else {
                return failure(provider, "The provider usage request failed (HTTP \(response.statusCode)).")
            }
            var data = Data()
            if response.expectedContentLength > maximumResponseBytes {
                return failure(provider, "The provider usage response was too large.")
            }
            for try await byte in bytes {
                guard data.count < maximumResponseBytes else {
                    return failure(provider, "The provider usage response was too large.")
                }
                data.append(byte)
            }
            return try CustomProviderUsageParser.parse(data)
        } catch is CancellationError {
            return failure(provider, "Usage-limit refresh was cancelled.")
        } catch {
            return failure(provider, "The provider usage endpoint is unavailable.")
        }
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let original = task.originalRequest?.url,
              let redirected = request.url,
              Self.sameOrigin(original, redirected),
              CustomProviderEndpoint.isSafeBaseURL(redirected)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private func applyHeaders(_ provider: CustomCodexProvider, to request: inout URLRequest) {
        for (name, value) in provider.directHeaders where Self.isSafeHeader(name, value: value) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        for (name, environmentName) in provider.environmentHeaders {
            guard let value = ProcessInfo.processInfo.environment[environmentName],
                  Self.isSafeHeader(name, value: value)
            else { continue }
            request.setValue(value, forHTTPHeaderField: name)
        }
        let token = provider.environmentKey.flatMap {
            ProcessInfo.processInfo.environment[$0]
        } ?? provider.bearerToken
        if let token, Self.isSafeHeader("Authorization", value: token) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func failure(_ provider: CustomCodexProvider, _ message: String) -> ProfileRateLimits {
        ProfileRateLimits(errorMessage: "\(provider.name): \(message)")
    }

    private static func usageURL(_ provider: CustomCodexProvider) -> URL? {
        CustomProviderEndpoint.usageURL(provider)
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }

    private static func isSafeHeader(_ name: String, value: String) -> Bool {
        !name.isEmpty
            && !name.contains(where: { $0 == "\r" || $0 == "\n" || $0 == ":" })
            && !value.contains(where: { $0 == "\r" || $0 == "\n" })
    }
}

enum CustomProviderEndpoint {
    static func usageURL(
        _ provider: CustomCodexProvider,
        now: Date = Date()
    ) -> URL? {
        guard isSafeBaseURL(provider.baseURL) else { return nil }
        guard var components = URLComponents(
            url: provider.baseURL
                .appendingPathComponent("organization")
                .appendingPathComponent("usage")
                .appendingPathComponent("completions"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        var queryParameters = provider.queryParameters
        let endTime = Int64(now.timeIntervalSince1970)
        queryParameters["start_time"] = String(endTime - 7 * 24 * 60 * 60)
        queryParameters["end_time"] = String(endTime)
        queryParameters["bucket_width"] = "1d"
        queryParameters["limit"] = "7"
        let configuredItems = queryParameters.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        components.queryItems = (components.queryItems ?? []) + configuredItems
        return components.url
    }

    static func isSafeBaseURL(_ url: URL) -> Bool {
        guard url.user == nil,
              url.password == nil,
              url.fragment == nil,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased()
        else {
            return false
        }
        if scheme == "https" { return true }
        guard scheme == "http" else { return false }
        return host == "localhost" || host == "::1" || isIPv4Loopback(host)
    }

    private static func isIPv4Loopback(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets[0] == "127" else {
            return false
        }
        return octets.allSatisfy { octet in
            guard !octet.isEmpty, octet.allSatisfy(\.isNumber) else {
                return false
            }
            return UInt8(octet) != nil
        }
    }
}

enum CustomProviderUsageParser {
    static func parse(
        _ data: Data,
        fetchedAt: Date = Date()
    ) throws -> ProfileRateLimits {
        let page = try JSONDecoder().decode(OrganizationCompletionsUsagePage.self, from: data)
        guard !page.data.isEmpty,
              let startsAt = page.data.map(\.startTime).min(),
              let endsAt = page.data.map(\.endTime).max()
        else { throw CustomProviderUsageError.missingBuckets }
        let results = page.data.flatMap(\.results)
        return ProfileRateLimits(
            apiUsage: APIUsageSummary(
                inputTokens: results.reduce(0) { $0 + $1.inputTokens },
                outputTokens: results.reduce(0) { $0 + $1.outputTokens },
                cachedInputTokens: results.reduce(0) { $0 + $1.cachedInputTokens },
                requestCount: results.reduce(0) { $0 + $1.requestCount },
                startsAt: Date(timeIntervalSince1970: TimeInterval(startsAt)),
                endsAt: Date(timeIntervalSince1970: TimeInterval(endsAt))
            ),
            fetchedAt: fetchedAt
        )
    }
}

private struct OrganizationCompletionsUsagePage: Decodable {
    var data: [OrganizationCompletionsUsageBucket]
}

private struct OrganizationCompletionsUsageBucket: Decodable {
    var startTime: Int64
    var endTime: Int64
    var results: [OrganizationCompletionsUsageResult]

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case results
    }
}

private struct OrganizationCompletionsUsageResult: Decodable {
    var inputTokens: Int64
    var outputTokens: Int64
    var cachedInputTokens: Int64
    var requestCount: Int64

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cachedInputTokens = "input_cached_tokens"
        case requestCount = "num_model_requests"
    }
}

private enum CustomProviderUsageError: Error {
    case missingBuckets
}
