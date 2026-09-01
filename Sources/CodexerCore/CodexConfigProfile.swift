import Foundation

public struct CodexConfigProfile: Codable, Hashable, Identifiable, RawRepresentable, Sendable {
    public let rawValue: String

    public var id: String { rawValue }
    public var name: String { rawValue }
    public var displayName: String {
        rawValue.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(validating name: String) throws {
        guard Self.isValidName(name) else {
            throw CodexConfigProfileError.invalidName(name)
        }
        rawValue = name
    }

    public func configurationURL(in codexHomeURL: URL) -> URL {
        codexHomeURL.appendingPathComponent("\(rawValue).config.toml", isDirectory: false)
    }

    public func validate(in codexHomeURL: URL) throws {
        guard Self.isValidName(rawValue) else {
            throw CodexConfigProfileError.invalidName(rawValue)
        }
        let url = configurationURL(in: codexHomeURL)
        do {
            _ = try BoundedFileReader.data(
                at: url,
                maximumBytes: LocalControlFileLimit.providerConfiguration
            )
        } catch {
            throw CodexConfigProfileError.unavailable(url.path)
        }
    }

    public static func discover(in codexHomeURL: URL) -> [CodexConfigProfile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: codexHomeURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        var profiles: [CodexConfigProfile] = []
        var inspectedCount = 0
        while inspectedCount < 256, let url = enumerator.nextObject() as? URL {
            inspectedCount += 1
            let suffix = ".config.toml"
            guard url.lastPathComponent.hasSuffix(suffix) else { continue }
            let name = String(url.lastPathComponent.dropLast(suffix.count))
            guard let profile = try? CodexConfigProfile(validating: name),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  (try? profile.validate(in: codexHomeURL)) != nil
            else {
                continue
            }
            profiles.append(profile)
        }
        return profiles.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    public static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48 ... 57, 65 ... 90, 97 ... 122, 45, 95:
                true
            default:
                false
            }
        }
    }
}

public enum CodexLaunchProfileSelection: Codable, Hashable, Sendable {
    case useDefault
    case builtIn
    case named(CodexConfigProfile)
}

public enum CodexConfigProfileError: Error, LocalizedError, Equatable {
    case invalidName(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidName(name):
            "The Codex profile name is invalid: \(name)"
        case let .unavailable(path):
            "The Codex profile configuration is missing or unsafe at \(path)."
        }
    }
}
