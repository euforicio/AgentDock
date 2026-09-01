import Foundation

public struct CodexProviderProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var executableURL: URL

    public init(id: UUID = UUID(), name: String, executableURL: URL) {
        self.id = id
        self.name = name
        self.executableURL = executableURL
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? executableURL.lastPathComponent : trimmed
    }

    public func validate(fileManager: FileManager = .default) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw CodexProviderProfileError.invalidName
        }
        guard executableURL.isFileURL,
              executableURL.path.hasPrefix("/"),
              let values = try? executableURL.resourceValues(
                  forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              fileManager.isExecutableFile(atPath: executableURL.path)
        else {
            throw CodexProviderProfileError.invalidExecutable(executableURL.path)
        }
    }
}

public enum CodexProviderProfileError: Error, LocalizedError, Equatable {
    case invalidName
    case invalidExecutable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            "Provider profile name cannot be empty or contain control characters."
        case let .invalidExecutable(path):
            "The provider profile executable is missing, unsafe, or not executable at \(path)."
        }
    }
}

public enum CodexProviderLaunch {
    public static let cliPathEnvironmentKey = "CODEX_CLI_PATH"

    public static func builtInExecutableURL(codexAppURL: URL) -> URL {
        codexAppURL.appendingPathComponent("Contents/Resources/codex", isDirectory: false)
    }

    public static func launchEnvironment(
        base: [String: String],
        configuration: IsolatedCodexLaunchConfiguration
    ) -> [String: String] {
        var environment = base
        environment["CODEX_HOME"] = configuration.codexHomePath
        if let executableURL = configuration.codexProviderExecutableURL {
            environment[cliPathEnvironmentKey] = executableURL.path
        } else {
            environment[cliPathEnvironmentKey] = builtInExecutableURL(
                codexAppURL: configuration.codexAppURL
            ).path
        }
        return environment
    }

    public static func stockLaunchEnvironment(
        base: [String: String],
        codexAppURL: URL
    ) -> [String: String] {
        var environment = base
        environment.removeValue(forKey: "CODEX_HOME")
        environment[cliPathEnvironmentKey] = builtInExecutableURL(codexAppURL: codexAppURL).path
        return environment
    }
}
