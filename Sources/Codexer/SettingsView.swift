import AppKit
import CodexerCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: CodexerModel
    @EnvironmentObject private var updater: AppUpdater
    @State private var section: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.icon)
                    .font(.system(size: 14))
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 230)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                    Text("Settings")
                        .font(.system(size: 13))
                    Spacer()
                    Text(appVersion)
                        .font(.system(size: 13))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .overlay(alignment: .top) { Divider() }
            }
        } detail: {
            sectionContent
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("AgentDock — Settings")
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .frame(
            minWidth: 780,
            idealWidth: 840,
            maxWidth: 880,
            minHeight: 560,
            idealHeight: 590,
            maxHeight: 620
        )
        .navigationSplitViewStyle(.balanced)
        .background(SettingsWindowConfigurator())
        .preferredColorScheme(preferredColorScheme)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .general: general
        case .providerApps: providerApps
        case .privacy: privacy
        case .about: about
        }
    }

    private var general: some View {
        SettingsPage(title: "General") {
            SettingsRow("Appearance") {
                Picker("Appearance", selection: appearanceBinding) {
                    ForEach(AgentDockAppearance.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            SettingsRow("Default View") {
                Picker("Default View", selection: defaultViewBinding) {
                    ForEach(AgentDockDefaultView.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            SettingsRow("Refresh profile activity") {
                HStack(spacing: 10) {
                    Toggle("", isOn: refreshBinding).labelsHidden()
                    Picker("Refresh Interval", selection: refreshIntervalBinding) {
                        ForEach(AgentDockPreferencesStore.allowedIntervals, id: \.self) { minutes in
                            Text(minutes == 1 ? "Every minute" : "Every \(minutes) minutes")
                                .tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .disabled(!model.preferences.refreshProfileActivity)
                }
            }
            SettingsRow("Show status in profile list") {
                Toggle("", isOn: showStatusBinding).labelsHidden()
            }

            SettingsSectionHeader("Updates")
            SettingsRow("Check for updates automatically") {
                Toggle("", isOn: automaticChecksBinding)
                    .labelsHidden()
                    .disabled(!updater.isConfigured)
            }
            SettingsRow("Download and install updates automatically") {
                Toggle("", isOn: automaticDownloadsBinding)
                    .labelsHidden()
                    .disabled(!updater.isConfigured || !updater.automaticallyChecksForUpdates)
            }
            Text(
                updater.isConfigured
                    ? "Update preferences are stored by Sparkle. Automatic installation completes when AgentDock can safely relaunch."
                    : "Automatic updates are unavailable in this development build."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            SettingsSectionHeader("Provider Apps")
            ForEach(DesktopProduct.allCases) { product in
                ProviderSettingsRow(product: product)
            }

            SettingsSectionHeader("Data & Privacy")
            SettingsRow("Profiles and chat history are stored locally") {
                Button("Manage…") { section = .privacy }
            }

            Button("Restore Defaults") {
                model.restorePreferences()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 14)

            Text("AgentDock.app  \(appVersion)   •   Settings save automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
    }

    private var providerApps: some View {
        SettingsPage(title: "Provider Apps") {
            SettingsSectionHeader("Provider Apps")
            ForEach(DesktopProduct.allCases) { product in
                ProviderSettingsRow(product: product)
            }
            Text("AgentDock launches only signed, supported provider apps selected here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
    }

    private var privacy: some View {
        SettingsPage(title: "Data & Privacy") {
            SettingsSectionHeader("Local Data")
            SettingsRow("Profiles and chat history are stored locally") {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        ProfileStore.defaultRootDirectory()
                    ])
                }
            }
            Text(
                "AgentDock reads only managed profile metadata and supported local Codex session records. It does not upload profile data or provide cloud synchronization."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)

            SettingsSectionHeader("Provider Data")
            Text("Provider apps may use their own network services and account storage. AgentDock's isolation boundary is described in the project documentation.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
        }
    }

    private var about: some View {
        SettingsPage(title: "About") {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AgentDock").font(.system(size: 17, weight: .semibold))
                    Text("Version \(appVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Native local profiles for Codex and Claude Desktop.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .controlSize(.regular)
                .disabled(!updater.isConfigured)
            }
            .padding(.vertical, 10)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.preferences.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }

    private var appearanceBinding: Binding<AgentDockAppearance> {
        Binding(get: { model.preferences.appearance }, set: { model.preferences.appearance = $0 })
    }

    private var defaultViewBinding: Binding<AgentDockDefaultView> {
        Binding(get: { model.preferences.defaultView }, set: { model.preferences.defaultView = $0 })
    }

    private var refreshBinding: Binding<Bool> {
        Binding(get: { model.preferences.refreshProfileActivity }, set: { model.preferences.refreshProfileActivity = $0 })
    }

    private var refreshIntervalBinding: Binding<Int> {
        Binding(get: { model.preferences.refreshIntervalMinutes }, set: { model.preferences.refreshIntervalMinutes = $0 })
    }

    private var showStatusBinding: Binding<Bool> {
        Binding(get: { model.preferences.showStatusInProfileList }, set: { model.preferences.showStatusInProfileList = $0 })
    }

    private var automaticChecksBinding: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var automaticDownloadsBinding: Binding<Bool> {
        Binding(
            get: { updater.automaticallyDownloadsUpdates },
            set: { updater.setAutomaticallyDownloadsUpdates($0) }
        )
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .padding(.bottom, 12)
                Divider()
                content
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(AgentDockPalette.graphite)
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let height: CGFloat
    @ViewBuilder let accessory: Accessory

    init(_ title: String, height: CGFloat = 48, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.height = height
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
            Spacer()
            accessory
        }
        .padding(.horizontal, 10)
        .frame(minHeight: height)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct SettingsSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .tracking(0.35)
            .padding(.top, 14)
            .padding(.bottom, 7)
            .overlay(alignment: .bottom) { Divider() }
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedWhite: 0.082, alpha: 1)
        window.minSize = NSSize(width: 780, height: 560)
        window.maxSize = NSSize(width: 880, height: 620)
    }
}

private struct ProviderSettingsRow: View {
    @EnvironmentObject private var model: CodexerModel
    let product: DesktopProduct

    var body: some View {
        HStack(spacing: 12) {
            ProviderIconView(product: product, appURL: model.appURL(for: product), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(product.displayName).app")
                    .font(.system(size: 14, weight: .semibold))
                Text("Version \(version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                StatusDot(isRunning: isAvailable, size: 7)
                Text(isAvailable ? "Found" : "Not Found")
                    .font(.system(size: 12))
                    .foregroundStyle(isAvailable ? Color.green : Color.orange)
            }
            .frame(width: 90, alignment: .leading)
            Text(abbreviatedPath)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .trailing)
            Button("Change…") { model.chooseApp(product) }
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 62)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var isAvailable: Bool {
        FileManager.default.fileExists(atPath: model.appURL(for: product).path)
    }

    private var version: String {
        let bundle = Bundle(url: model.appURL(for: product))
        return bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var abbreviatedPath: String {
        model.appURL(for: product).path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case providerApps
    case privacy
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .providerApps: "Provider Apps"
        case .privacy: "Data & Privacy"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .providerApps: "square.grid.2x2"
        case .privacy: "lock"
        case .about: "info.circle"
        }
    }
}
