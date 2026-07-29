import AppKit
import CoreGraphics
import Darwin
import Foundation
import Security

public struct IsolatedCodexLaunchConfiguration: Codable, Equatable, Sendable {
    public var product: DesktopProduct?
    public var codexAppPath: String
    public var codexHomePath: String
    public var electronUserDataPath: String
    public var claudeUserDataPath: String?
    public var mcpOAuthCallbackPort: Int?
    public var profileID: UUID?
    public var profileSlug: String?

    public init(
        codexAppURL: URL,
        codexHomeURL: URL,
        electronUserDataURL: URL,
        mcpOAuthCallbackPort: Int? = nil,
        profileID: UUID? = nil,
        profileSlug: String? = nil
    ) {
        product = .codex
        codexAppPath = codexAppURL.path
        codexHomePath = codexHomeURL.path
        electronUserDataPath = electronUserDataURL.path
        claudeUserDataPath = nil
        self.mcpOAuthCallbackPort = mcpOAuthCallbackPort
        self.profileID = profileID
        self.profileSlug = profileSlug
    }

    public init(profile: CodexProfile, codexAppURL: URL) {
        product = profile.product
        codexAppPath = codexAppURL.path
        codexHomePath = profile.product == .codex ? profile.codexHomePath.path : ""
        electronUserDataPath = profile.product == .codex ? profile.electronUserDataPath.path : ""
        claudeUserDataPath = profile.product == .claude ? profile.claudeUserDataPath.path : nil
        mcpOAuthCallbackPort = profile.product == .codex ? profile.mcpOAuthCallbackPort : nil
        profileID = profile.id
        profileSlug = profile.slug
    }

    public var resolvedProduct: DesktopProduct { product ?? .codex }
    public var appURL: URL { codexAppURL }
    public var codexAppURL: URL { URL(fileURLWithPath: codexAppPath) }
    public var codexHomeURL: URL { URL(fileURLWithPath: codexHomePath, isDirectory: true) }
    public var electronUserDataURL: URL { URL(fileURLWithPath: electronUserDataPath, isDirectory: true) }
    public var claudeUserDataURL: URL? {
        claudeUserDataPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    public var appExecutableURL: URL {
        Self.appExecutableURL(for: codexAppURL)
    }

    public static func appExecutableURL(for codexAppURL: URL) -> URL {
        let infoPlistURL = codexAppURL.appendingPathComponent("Contents/Info.plist")
        let executableName: String? = {
            guard
                let data = try? Data(contentsOf: infoPlistURL),
                let plist = try? PropertyListSerialization.propertyList(
                    from: data,
                    format: nil
                ) as? [String: Any]
            else {
                return nil
            }
            return plist["CFBundleExecutable"] as? String
        }()

        return codexAppURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(executableName ?? "Codex")
    }
}

public struct CodexInstanceStatus: Equatable, Sendable {
    public var processIDs: [Int32]

    public init(processIDs: [Int32] = []) {
        self.processIDs = processIDs.sorted()
    }

    public var isRunning: Bool { !processIDs.isEmpty }
    public var primaryProcessID: Int32? { processIDs.first }
}

public enum CodexOpenOutcome: Equatable, Sendable {
    case launched(processID: Int32)
    case focused(processID: Int32)
}

public enum CodexCloseOutcome: Equatable, Sendable {
    case alreadyStopped
    case closed(processIDs: [Int32])
}

public protocol CodexAppValidating: Sendable {
    func validateCodexApp(at url: URL) throws
}

public struct OfficialCodexAppValidator: CodexAppValidating, @unchecked Sendable {
    public static let bundleIdentifier = "com.openai.codex"
    public static let teamIdentifier = "2DC432GLL2"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func validateCodexApp(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CodexLauncherError.codexAppMissing(url.path)
        }

        let infoPlist = url.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoPlist),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            plist["CFBundleIdentifier"] as? String == Self.bundleIdentifier
        else {
            throw CodexLauncherError.invalidCodexBundle(url.path)
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            throw CodexLauncherError.invalidCodexSignature(url.path)
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(Self.requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
        else {
            throw CodexLauncherError.invalidCodexSignature(url.path)
        }
    }

    fileprivate static var requirementText: String {
        "anchor apple generic and identifier \"\(bundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }

    fileprivate static var teamRequirementText: String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

public protocol CodexProcessSnapshotProviding: Sendable {
    func processSnapshot() throws -> String
}

public struct SystemCodexProcessSnapshotProvider: CodexProcessSnapshotProviding {
    public init() {}

    public func processSnapshot() throws -> String {
        let result: BoundedSubprocessResult
        do {
            result = try BoundedSubprocess.run(
                executableURL: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-ax", "-o", "pid=,command="],
                timeout: 3,
                maximumOutputBytes: 8 * 1_024 * 1_024
            )
        } catch {
            throw CodexLauncherError.processInspectionUnavailable
        }
        guard !result.exceededOutputLimit else {
            throw CodexLauncherError.processInspectionUnavailable
        }
        guard result.terminationStatus == 0 else {
            throw CodexLauncherError.processInspectionFailed(result.terminationStatus)
        }
        return String(decoding: result.output, as: UTF8.self)
    }
}

public enum CodexInstanceDiscovery {
    public static func canonicalUserDataPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    public static func processIDsByUserDataPath(
        in processSnapshot: String,
        appExecutableURL: URL
    ) -> [String: [Int32]] {
        let commandPrefix = "\(appExecutableURL.path) --user-data-dir="
        var result: [String: [Int32]] = [:]

        for line in processSnapshot.split(whereSeparator: \.isNewline) {
            let trimmed = line.drop(while: \.isWhitespace)
            guard let separator = trimmed.firstIndex(where: \.isWhitespace) else { continue }
            let pidText = trimmed[..<separator]
            let command = trimmed[separator...].drop(while: \.isWhitespace)
            guard command.hasPrefix(commandPrefix),
                  let processID = Int32(pidText)
            else {
                continue
            }
            let userDataPath = canonicalUserDataPath(
                String(command.dropFirst(commandPrefix.count))
            )
            result[userDataPath, default: []].append(processID)
        }

        return result.mapValues { $0.sorted() }
    }

    public static func processIDs(
        in processSnapshot: String,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> [Int32] {
        processIDsByUserDataPath(
            in: processSnapshot,
            appExecutableURL: configuration.appExecutableURL
        )[canonicalUserDataPath(configuration.electronUserDataPath)] ?? []
    }

    public static func stockProcessIDs(
        in processSnapshot: String,
        appExecutableURL: URL
    ) -> [Int32] {
        let executable = appExecutableURL.standardizedFileURL.path
        return processSnapshot.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.drop(while: \.isWhitespace)
            guard let separator = trimmed.firstIndex(where: \.isWhitespace),
                  let processID = Int32(trimmed[..<separator])
            else {
                return nil
            }
            let command = String(trimmed[separator...].drop(while: \.isWhitespace))
            guard command == executable || command.hasPrefix("\(executable) ") else {
                return nil
            }
            return command.contains("--user-data-dir=") ? nil : processID
        }.sorted()
    }

    public static func profileProcessIDs(
        in processSnapshot: String,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> [Int32] {
        let profilePath = canonicalUserDataPath(configuration.electronUserDataPath)
        let appBundlePrefix = configuration.codexAppURL
            .standardizedFileURL
            .appendingPathComponent("Contents")
            .path
        let profileArguments = [
            "--user-data-dir=\(profilePath)",
            "--database=\(profilePath)/Crashpad"
        ]

        return processSnapshot.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.drop(while: \.isWhitespace)
            guard let separator = trimmed.firstIndex(where: \.isWhitespace),
                  let processID = Int32(trimmed[..<separator])
            else {
                return nil
            }
            let command = String(trimmed[separator...].drop(while: \.isWhitespace))
            guard command.hasPrefix(appBundlePrefix) else { return nil }
            return profileArguments.contains(where: { containsArgument($0, in: command) })
                ? processID
                : nil
        }.sorted()
    }

    private static func containsArgument(_ argument: String, in command: String) -> Bool {
        guard let range = command.range(of: argument) else { return false }
        let beginsArgument = range.lowerBound == command.startIndex
            || command[command.index(before: range.lowerBound)].isWhitespace
        let followsArgument = range.upperBound == command.endIndex
            || command[range.upperBound].isWhitespace
        return beginsArgument && followsArgument
    }
}

public protocol CodexWorkspaceLaunching: Sendable {
    func launch(configuration: IsolatedCodexLaunchConfiguration) async throws -> Int32
    func launchStock(codexAppURL: URL) async throws -> Int32
}

public extension CodexWorkspaceLaunching {
    func launchStock(codexAppURL _: URL) async throws -> Int32 {
        throw CodexLauncherError.launchDidNotReturnProcess
    }
}

public struct SystemCodexWorkspaceLauncher: CodexWorkspaceLaunching {
    public init() {}

    public func launch(configuration: IsolatedCodexLaunchConfiguration) async throws -> Int32 {
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = true
        openConfiguration.addsToRecentItems = false
        openConfiguration.allowsRunningApplicationSubstitution = false
        openConfiguration.createsNewApplicationInstance = true
        openConfiguration.arguments = [
            "--user-data-dir=\(configuration.electronUserDataPath)"
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = configuration.codexHomePath
        openConfiguration.environment = environment

        let application = try await NSWorkspace.shared.openApplication(
            at: configuration.codexAppURL,
            configuration: openConfiguration
        )
        let processID = application.processIdentifier
        guard processID > 0 else {
            throw CodexLauncherError.launchDidNotReturnProcess
        }
        return processID
    }

    public func launchStock(codexAppURL: URL) async throws -> Int32 {
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = true
        openConfiguration.addsToRecentItems = false
        openConfiguration.allowsRunningApplicationSubstitution = false
        openConfiguration.createsNewApplicationInstance = true
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CODEX_HOME")
        openConfiguration.environment = environment

        let application = try await NSWorkspace.shared.openApplication(
            at: codexAppURL,
            configuration: openConfiguration
        )
        let processID = application.processIdentifier
        guard processID > 0 else {
            throw CodexLauncherError.launchDidNotReturnProcess
        }
        return processID
    }
}

public protocol CodexApplicationLifecycleControlling: Sendable {
    func focus(processID: Int32, configuration: IsolatedCodexLaunchConfiguration) -> Bool
    func requestPresentation(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> Bool
    func isPresentingWindow(processID: Int32) -> Bool
    func terminate(processID: Int32, configuration: IsolatedCodexLaunchConfiguration) -> Bool
    func isRunning(processID: Int32) -> Bool
    func isVerifiedRunning(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> Bool
    func terminateAuxiliary(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration,
        processSnapshot: String
    ) -> Bool
    func isVerifiedProfileProcess(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration,
        processSnapshot: String
    ) -> Bool
    func invalidateUnverifiedLaunch(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    )
    func focusStock(processID: Int32, codexAppURL: URL) -> Bool
    func isVerifiedStockRunning(processID: Int32, codexAppURL: URL) -> Bool
    func invalidateUnverifiedStockLaunch(processID: Int32, codexAppURL: URL)
}

public extension CodexApplicationLifecycleControlling {
    func requestPresentation(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> Bool {
        focus(processID: processID, configuration: configuration)
    }

    func isPresentingWindow(processID: Int32) -> Bool {
        isRunning(processID: processID)
    }

    func isVerifiedRunning(
        processID: Int32,
        configuration _: IsolatedCodexLaunchConfiguration
    ) -> Bool {
        isRunning(processID: processID)
    }

    func invalidateUnverifiedLaunch(
        processID _: Int32,
        configuration _: IsolatedCodexLaunchConfiguration
    ) {}

    func focusStock(processID _: Int32, codexAppURL _: URL) -> Bool { false }

    func isVerifiedStockRunning(processID: Int32, codexAppURL _: URL) -> Bool {
        isRunning(processID: processID)
    }

    func invalidateUnverifiedStockLaunch(processID _: Int32, codexAppURL _: URL) {}

    func terminateAuxiliary(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration,
        processSnapshot _: String
    ) -> Bool {
        terminate(processID: processID, configuration: configuration)
    }

    func isVerifiedProfileProcess(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration,
        processSnapshot _: String
    ) -> Bool {
        isVerifiedRunning(processID: processID, configuration: configuration)
    }
}

public struct SystemCodexApplicationLifecycleController: CodexApplicationLifecycleControlling {
    public init() {}

    public func focus(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> Bool {
        guard let application = verifiedApplication(
            processID: processID,
            configuration: configuration
        ) else {
            return false
        }
        sendReopenEvent(to: processID)
        return application.activate(options: [.activateAllWindows])
    }

    public func requestPresentation(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> Bool {
        focus(processID: processID, configuration: configuration)
    }

    public func isPresentingWindow(processID: Int32) -> Bool {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        return windowInfo.contains { window in
            guard
                (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
                (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds)
            else {
                return false
            }
            return frame.width > 0 && frame.height > 0
        }
    }

    public func terminate(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> Bool {
        guard let application = verifiedApplication(
            processID: processID,
            configuration: configuration
        ) else {
            return !isStillClaimingProfile(
                processID: processID,
                configuration: configuration
            )
        }
        if application.terminate() {
            return true
        }
        return kill(processID, SIGTERM) == 0 || errno == ESRCH
    }

    public func isRunning(processID: Int32) -> Bool {
        guard let application = NSRunningApplication(processIdentifier: processID) else {
            return false
        }
        return !application.isTerminated
    }

    public func isVerifiedRunning(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> Bool {
        verifiedApplication(
            processID: processID,
            configuration: configuration
        ) != nil
    }

    public func invalidateUnverifiedLaunch(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) {
        officialMainApplication(
            processID: processID,
            configuration: configuration
        )?.terminate()
    }

    public func focusStock(processID: Int32, codexAppURL: URL) -> Bool {
        guard let application = officialMainApplication(
            processID: processID,
            codexAppURL: codexAppURL
        ), isStockProcess(processID: processID, codexAppURL: codexAppURL) else {
            return false
        }
        sendReopenEvent(to: processID)
        return application.activate(options: [.activateAllWindows])
    }

    public func isVerifiedStockRunning(processID: Int32, codexAppURL: URL) -> Bool {
        officialMainApplication(processID: processID, codexAppURL: codexAppURL) != nil
            && isStockProcess(processID: processID, codexAppURL: codexAppURL)
    }

    public func invalidateUnverifiedStockLaunch(processID: Int32, codexAppURL: URL) {
        officialMainApplication(processID: processID, codexAppURL: codexAppURL)?.terminate()
    }

    public func terminateAuxiliary(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration,
        processSnapshot: String
    ) -> Bool {
        guard isVerifiedProfileProcess(
            processID: processID,
            configuration: configuration,
            processSnapshot: processSnapshot
        ) else {
            return kill(processID, 0) != 0 && errno == ESRCH
        }
        return kill(processID, SIGTERM) == 0 || errno == ESRCH
    }

    public func isVerifiedProfileProcess(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration,
        processSnapshot: String
    ) -> Bool {
        guard hasOfficialDynamicSignature(
            processID: processID,
            requirementText: OfficialCodexAppValidator.teamRequirementText
        )
        else {
            return false
        }
        return CodexInstanceDiscovery.profileProcessIDs(
            in: processSnapshot,
            configuration: configuration
        ).contains(processID)
    }

    private func sendReopenEvent(to processID: Int32) {
        let target = NSAppleEventDescriptor(processIdentifier: processID)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        _ = try? event.sendEvent(options: .noReply, timeout: 1)
    }

    private func isStillClaimingProfile(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> Bool {
        guard let snapshot = try? SystemCodexProcessSnapshotProvider().processSnapshot() else {
            return true
        }
        return CodexInstanceDiscovery.profileProcessIDs(
            in: snapshot,
            configuration: configuration
        ).contains(processID)
    }

    private func verifiedApplication(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> NSRunningApplication? {
        guard let application = officialMainApplication(
            processID: processID,
            configuration: configuration
        ) else { return nil }
        guard let snapshot = try? SystemCodexProcessSnapshotProvider().processSnapshot(),
              CodexInstanceDiscovery.processIDs(
                in: snapshot,
                configuration: configuration
              ).contains(processID)
        else {
            return nil
        }
        return application
    }

    private func officialMainApplication(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) -> NSRunningApplication? {
        officialMainApplication(
            processID: processID,
            codexAppURL: configuration.codexAppURL
        )
    }

    private func officialMainApplication(
        processID: Int32,
        codexAppURL: URL
    ) -> NSRunningApplication? {
        guard let application = NSRunningApplication(processIdentifier: processID),
              application.bundleIdentifier == OfficialCodexAppValidator.bundleIdentifier,
              application.executableURL?.standardizedFileURL
                == IsolatedCodexLaunchConfiguration.appExecutableURL(for: codexAppURL)
                    .standardizedFileURL,
              hasOfficialDynamicSignature(
                processID: processID,
                requirementText: OfficialCodexAppValidator.requirementText
              )
        else {
            return nil
        }
        return application
    }

    private func isStockProcess(processID: Int32, codexAppURL: URL) -> Bool {
        guard let snapshot = try? SystemCodexProcessSnapshotProvider().processSnapshot() else {
            return false
        }
        return CodexInstanceDiscovery.stockProcessIDs(
            in: snapshot,
            appExecutableURL: IsolatedCodexLaunchConfiguration.appExecutableURL(for: codexAppURL)
        ).contains(processID)
    }

    private func hasOfficialDynamicSignature(
        processID: Int32,
        requirementText: String
    ) -> Bool {
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: processID)
        ] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code
        else {
            return false
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            [],
            &requirement
        ) == errSecSuccess,
              let requirement
        else {
            return false
        }
        return SecCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSStrictValidate),
            requirement
        ) == errSecSuccess
    }
}

public actor CodexInstanceController {
    private let fileManager: FileManager
    private let validator: any CodexAppValidating
    private let processSnapshotProvider: any CodexProcessSnapshotProviding
    private let workspaceLauncher: any CodexWorkspaceLaunching
    private let lifecycleController: any CodexApplicationLifecycleControlling
    private let closeTimeout: Duration
    private let closePollInterval: Duration
    private let launchValidationTimeout: Duration
    private let processTreeProvider: any ProcessTreeSnapshotProviding
    private let processIdentitySignaler: any ProcessIdentitySignaling

    public init(
        fileManager: FileManager = .default,
        validator: any CodexAppValidating = OfficialCodexAppValidator(),
        processSnapshotProvider: any CodexProcessSnapshotProviding = SystemCodexProcessSnapshotProvider(),
        workspaceLauncher: any CodexWorkspaceLaunching = SystemCodexWorkspaceLauncher(),
        lifecycleController: any CodexApplicationLifecycleControlling = SystemCodexApplicationLifecycleController(),
        closeTimeout: Duration = .seconds(5),
        closePollInterval: Duration = .milliseconds(100),
        launchValidationTimeout: Duration = .seconds(2),
        processTreeProvider: any ProcessTreeSnapshotProviding = SystemProcessTreeSnapshotProvider(),
        processIdentitySignaler: (any ProcessIdentitySignaling)? = nil
    ) {
        self.fileManager = fileManager
        self.validator = validator
        self.processSnapshotProvider = processSnapshotProvider
        self.workspaceLauncher = workspaceLauncher
        self.lifecycleController = lifecycleController
        self.closeTimeout = closeTimeout
        self.closePollInterval = closePollInterval
        self.launchValidationTimeout = launchValidationTimeout
        self.processTreeProvider = processTreeProvider
        self.processIdentitySignaler = processIdentitySignaler
            ?? SystemProcessIdentitySignaler(snapshotProvider: processTreeProvider)
    }

    public func status(
        for profile: CodexProfile,
        codexAppURL: URL
    ) throws -> CodexInstanceStatus {
        try status(configuration: IsolatedCodexLaunchConfiguration(profile: profile, codexAppURL: codexAppURL))
    }

    public func statuses(
        for profiles: [CodexProfile],
        codexAppURL: URL
    ) throws -> [CodexProfile.ID: CodexInstanceStatus] {
        let snapshot = try processSnapshotProvider.processSnapshot()
        let appExecutableURL = IsolatedCodexLaunchConfiguration.appExecutableURL(
            for: codexAppURL
        )
        let processIDsByPath = CodexInstanceDiscovery.processIDsByUserDataPath(
            in: snapshot,
            appExecutableURL: appExecutableURL
        )
        return Dictionary(uniqueKeysWithValues: profiles.map { profile in
            return (
                profile.id,
                CodexInstanceStatus(
                    processIDs: processIDsByPath[
                        CodexInstanceDiscovery.canonicalUserDataPath(
                            profile.electronUserDataPath.path
                        )
                    ] ?? []
                )
            )
        })
    }

    public func stockStatus(codexAppURL: URL) throws -> CodexInstanceStatus {
        let snapshot = try processSnapshotProvider.processSnapshot()
        return CodexInstanceStatus(
            processIDs: CodexInstanceDiscovery.stockProcessIDs(
                in: snapshot,
                appExecutableURL: IsolatedCodexLaunchConfiguration.appExecutableURL(
                    for: codexAppURL
                )
            )
        )
    }

    public func open(
        profile: CodexProfile,
        codexAppURL: URL
    ) async throws -> CodexOpenOutcome {
        try await open(configuration: IsolatedCodexLaunchConfiguration(profile: profile, codexAppURL: codexAppURL))
    }

    public func openStock(codexAppURL: URL) async throws -> CodexOpenOutcome {
        try validator.validateCodexApp(at: codexAppURL)

        if let processID = try stockStatus(codexAppURL: codexAppURL).primaryProcessID {
            guard lifecycleController.focusStock(
                processID: processID,
                codexAppURL: codexAppURL
            ) else {
                throw CodexLauncherError.couldNotFocus(processID)
            }
            return .focused(processID: processID)
        }

        try validator.validateCodexApp(at: codexAppURL)
        let processID = try await workspaceLauncher.launchStock(codexAppURL: codexAppURL)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: launchValidationTimeout)
        do {
            while clock.now < deadline {
                try Task.checkCancellation()
                if lifecycleController.isVerifiedStockRunning(
                    processID: processID,
                    codexAppURL: codexAppURL
                ) {
                    return .launched(processID: processID)
                }
                try await clock.sleep(for: .milliseconds(50))
            }
            try Task.checkCancellation()
            if lifecycleController.isVerifiedStockRunning(
                processID: processID,
                codexAppURL: codexAppURL
            ) {
                return .launched(processID: processID)
            }
        } catch {
            lifecycleController.invalidateUnverifiedStockLaunch(
                processID: processID,
                codexAppURL: codexAppURL
            )
            throw error
        }
        lifecycleController.invalidateUnverifiedStockLaunch(
            processID: processID,
            codexAppURL: codexAppURL
        )
        throw CodexLauncherError.launchedProcessFailedValidation(processID)
    }

    public func open(
        configuration: IsolatedCodexLaunchConfiguration
    ) async throws -> CodexOpenOutcome {
        guard configuration.resolvedProduct == .codex else {
            throw CodexLauncherError.invalidIsolationLayout(
                configuration.claudeUserDataURL?.deletingLastPathComponent().path
                    ?? configuration.codexHomeURL.deletingLastPathComponent().path
            )
        }
        try validator.validateCodexApp(at: configuration.codexAppURL)
        let operationLock = try await ProfileOperationLock.acquire(
            for: configuration.codexHomeURL.deletingLastPathComponent()
        )
        defer { withExtendedLifetime(operationLock) {} }
        try validateIsolationLayout(configuration)

        if let processID = try status(configuration: configuration).primaryProcessID {
            guard lifecycleController.focus(
                processID: processID,
                configuration: configuration
            ) else {
                throw CodexLauncherError.couldNotFocus(processID)
            }
            return .focused(processID: processID)
        }

        try validateMCPConfiguration(configuration)
        try validator.validateCodexApp(at: configuration.codexAppURL)
        let processID = try await workspaceLauncher.launch(configuration: configuration)
        let isVerified: Bool
        do {
            isVerified = try await waitForVerifiedLaunch(
                processID: processID,
                configuration: configuration
            )
        } catch {
            lifecycleController.invalidateUnverifiedLaunch(
                processID: processID,
                configuration: configuration
            )
            throw error
        }
        guard isVerified else {
            lifecycleController.invalidateUnverifiedLaunch(
                processID: processID,
                configuration: configuration
            )
            throw CodexLauncherError.launchedProcessFailedValidation(processID)
        }
        let didPresentWindow: Bool
        do {
            if lifecycleController.requestPresentation(
                processID: processID,
                configuration: configuration
            ) {
                didPresentWindow = try await waitForPresentedWindow(processID: processID)
            } else {
                didPresentWindow = false
            }
        } catch {
            _ = lifecycleController.terminate(
                processID: processID,
                configuration: configuration
            )
            throw error
        }
        guard didPresentWindow else {
            _ = lifecycleController.terminate(
                processID: processID,
                configuration: configuration
            )
            throw CodexLauncherError.launchedProcessDidNotPresentWindow(processID)
        }
        return .launched(processID: processID)
    }

    public func close(
        profile: CodexProfile,
        codexAppURL: URL
    ) async throws -> CodexCloseOutcome {
        let configuration = IsolatedCodexLaunchConfiguration(profile: profile, codexAppURL: codexAppURL)
        let operationLock = try await ProfileOperationLock.acquire(
            for: configuration.codexHomeURL.deletingLastPathComponent()
        )
        defer { withExtendedLifetime(operationLock) {} }
        let snapshot = try processSnapshotProvider.processSnapshot()
        let processIDs = CodexInstanceDiscovery.processIDs(
            in: snapshot,
            configuration: configuration
        )
        let profileProcessIDs = CodexInstanceDiscovery.profileProcessIDs(
            in: snapshot,
            configuration: configuration
        )
        guard !profileProcessIDs.isEmpty else { return .alreadyStopped }
        let processTree = try processTreeProvider.processTreeSnapshot()
        let descendants = SystemProcessTreeSnapshotProvider.descendants(
            of: Set(processIDs),
            in: processTree
        )
        let profileProcessIDSet = Set(profileProcessIDs)
        let capturedProfileProcesses = processTree.filter {
            profileProcessIDSet.contains($0.processID) && !processIDs.contains($0.processID)
        }
        let capturedProcesses = Array(Set(descendants + capturedProfileProcesses)).map { identity in
            var identity = identity
            identity.kernelStartKey = SystemProcessTreeSnapshotProvider.kernelStartKey(
                for: identity.processID
            )
            return identity
        }

        for processID in processIDs {
            guard lifecycleController.terminate(
                processID: processID,
                configuration: configuration
            ) else {
                throw CodexLauncherError.couldNotTerminate(processID)
            }
        }
        let auxiliarySnapshot = try processSnapshotProvider.processSnapshot()
        let auxiliaryProcessIDs = CodexInstanceDiscovery.profileProcessIDs(
            in: auxiliarySnapshot,
            configuration: configuration
        ).filter { !processIDs.contains($0) }
        for processID in auxiliaryProcessIDs {
            _ = lifecycleController.terminateAuxiliary(
                processID: processID,
                configuration: configuration,
                processSnapshot: auxiliarySnapshot
            )
        }
        try processIdentitySignaler.signal(
            SIGTERM,
            identities: Array(capturedProcesses.reversed())
        )

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: closeTimeout)
        while clock.now < deadline {
            let (remaining, remainingDescendants) = try remainingProcesses(
                configuration: configuration,
                captured: capturedProcesses
            )
            if remaining.isEmpty, remainingDescendants.isEmpty {
                return .closed(processIDs: processIDs)
            }
            try await clock.sleep(for: closePollInterval)
        }

        var (remaining, remainingDescendants) = try remainingProcesses(
            configuration: configuration,
            captured: capturedProcesses
        )
        if !remainingDescendants.isEmpty {
            try processIdentitySignaler.signal(SIGKILL, identities: remainingDescendants)
            try await clock.sleep(for: .milliseconds(100))
            (remaining, remainingDescendants) = try remainingProcesses(
                configuration: configuration,
                captured: capturedProcesses
            )
        }
        guard remaining.isEmpty, remainingDescendants.isEmpty else {
            let allRemaining = Set(remaining + remainingDescendants.map(\.processID)).sorted()
            throw CodexLauncherError.closeTimedOut(allRemaining)
        }
        return .closed(processIDs: processIDs)
    }

    public func validateCodexApp(at url: URL) throws {
        try validator.validateCodexApp(at: url)
    }

    private func status(
        configuration: IsolatedCodexLaunchConfiguration
    ) throws -> CodexInstanceStatus {
        let snapshot = try processSnapshotProvider.processSnapshot()
        return CodexInstanceStatus(
            processIDs: CodexInstanceDiscovery.processIDs(
                in: snapshot,
                configuration: configuration
            )
        )
    }

    private func waitForVerifiedLaunch(
        processID: Int32,
        configuration: IsolatedCodexLaunchConfiguration
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: launchValidationTimeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            if lifecycleController.isVerifiedRunning(
                processID: processID,
                configuration: configuration
            ) {
                return true
            }
            try await clock.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        return lifecycleController.isVerifiedRunning(
            processID: processID,
            configuration: configuration
        )
    }

    private func waitForPresentedWindow(processID: Int32) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: launchValidationTimeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            if lifecycleController.isPresentingWindow(processID: processID) {
                return true
            }
            try await clock.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        return lifecycleController.isPresentingWindow(processID: processID)
    }

    private func remainingProcesses(
        configuration: IsolatedCodexLaunchConfiguration,
        captured: [ProcessIdentity]
    ) throws -> ([Int32], [ProcessIdentity]) {
        let current = try processTreeProvider.processTreeSnapshot()
        let currentByPID = Dictionary(uniqueKeysWithValues: current.map { ($0.processID, $0) })
        let commandSnapshot = current.map { "\($0.processID) \($0.command)" }
            .joined(separator: "\n")
        let profileProcessIDs = CodexInstanceDiscovery.profileProcessIDs(
            in: commandSnapshot,
            configuration: configuration
        )
        let descendants = captured.filter { identity in
            guard let current = currentByPID[identity.processID] else { return false }
            return current.startKey == identity.startKey && current.command == identity.command
        }
        return (profileProcessIDs, descendants)
    }

    private func validateIsolationLayout(
        _ configuration: IsolatedCodexLaunchConfiguration
    ) throws {
        let profileDirectory = configuration.codexHomeURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let electronParent = configuration.electronUserDataURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard configuration.codexHomeURL.lastPathComponent == "CODEX_HOME",
              configuration.electronUserDataURL.lastPathComponent == "ElectronUserData",
              profileDirectory == electronParent
        else {
            throw CodexLauncherError.invalidIsolationLayout(profileDirectory.path)
        }

        for directory in [configuration.codexHomeURL, configuration.electronUserDataURL] {
            let values = try? directory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values?.isDirectory == true,
                  values?.isSymbolicLink != true,
                  directory.resolvingSymlinksInPath()
                    .deletingLastPathComponent().standardizedFileURL.path == profileDirectory.path
            else {
                throw CodexLauncherError.invalidIsolationLayout(profileDirectory.path)
            }
        }

        struct OwnershipMarker: Decodable {
            var profileID: UUID
            var product: DesktopProduct?
            var slug: String
        }
        let markerURL = profileDirectory.appendingPathComponent(".codexer-profile.json")
        guard let expectedID = configuration.profileID,
              let expectedSlug = configuration.profileSlug,
              let markerData = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(OwnershipMarker.self, from: markerData),
              marker.profileID == expectedID,
              marker.product == nil || marker.product == .codex,
              marker.slug == expectedSlug
        else {
            throw CodexLauncherError.invalidIsolationLayout(profileDirectory.path)
        }
    }

    private func validateMCPConfiguration(
        _ configuration: IsolatedCodexLaunchConfiguration
    ) throws {
        do {
            try CodexMCPConfiguration.validate(
                codexHomeURL: configuration.codexHomeURL,
                expectedCallbackPort: configuration.mcpOAuthCallbackPort
            )
            if validator is OfficialCodexAppValidator {
                try CodexMCPConfiguration.validateWithBundledCodex(
                    codexAppURL: configuration.codexAppURL,
                    codexHomeURL: configuration.codexHomeURL
                )
            }
        } catch {
            throw CodexLauncherError.invalidMCPConfiguration(
                configuration.codexHomeURL.appendingPathComponent("config.toml").path
            )
        }
    }
}

public enum CodexLauncherError: Error, LocalizedError, Equatable {
    case codexAppMissing(String)
    case invalidCodexBundle(String)
    case invalidCodexSignature(String)
    case invalidIsolationLayout(String)
    case invalidMCPConfiguration(String)
    case processInspectionFailed(Int32)
    case processInspectionUnavailable
    case launchDidNotReturnProcess
    case launchedProcessFailedValidation(Int32)
    case launchedProcessDidNotPresentWindow(Int32)
    case couldNotFocus(Int32)
    case couldNotTerminate(Int32)
    case closeTimedOut([Int32])

    public var errorDescription: String? {
        switch self {
        case let .codexAppMissing(path):
            "Codex.app was not found at \(path)."
        case let .invalidCodexBundle(path):
            "\(path) does not have the official Codex bundle identifier."
        case let .invalidCodexSignature(path):
            "\(path) is not signed by OpenAI with the expected Developer ID."
        case let .invalidIsolationLayout(path):
            "The Codex profile at \(path) is missing or has an invalid isolation layout."
        case let .invalidMCPConfiguration(path):
            "The Codex profile has an invalid MCP OAuth configuration at \(path)."
        case let .processInspectionFailed(status):
            "AgentDock could not inspect running Codex instances (ps exited with status \(status))."
        case .processInspectionUnavailable:
            "AgentDock could not safely inspect running Codex instances."
        case .launchDidNotReturnProcess:
            "macOS did not return the process for the new Codex instance."
        case let .launchedProcessFailedValidation(processID):
            "The launched process \(processID) did not match the signed official app and was stopped."
        case let .launchedProcessDidNotPresentWindow(processID):
            "Codex profile process \(processID) launched but did not present a window and was stopped."
        case let .couldNotFocus(processID):
            "Codex profile process \(processID) is running but could not be focused."
        case let .couldNotTerminate(processID):
            "Codex profile process \(processID) could not be asked to quit."
        case let .closeTimedOut(processIDs):
            "Codex did not quit cleanly. Still running: \(processIDs.map(String.init).joined(separator: ", "))."
        }
    }
}

public enum CodexAppLocator {
    public static func defaultCodexAppURL(fileManager: FileManager = .default) -> URL? {
        let defaultURL = URL(fileURLWithPath: "/Applications/Codex.app")
        if fileManager.fileExists(atPath: defaultURL.path) {
            return defaultURL
        }
        return nil
    }
}
