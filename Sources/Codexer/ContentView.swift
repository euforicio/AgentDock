import AppKit
import CodexerCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: CodexerModel
    @EnvironmentObject private var updater: AppUpdater
    @State private var profileSearch = ""
    @State private var showsSettings = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 270)
        } detail: {
            detail
        }
        .font(.system(size: 13))
        .preferredColorScheme(preferredColorScheme)
        .sheet(isPresented: $model.showAddProfile) {
            AddProfileSheet()
        }
        .sheet(isPresented: analyticsConsentBinding) {
            AnalyticsConsentView()
        }
        .sheet(isPresented: $model.showEditProfile) {
            if let profile = model.selectedProfile {
                EditProfileSheet(profile: profile)
            }
        }
        .alert("AgentDock Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Remove Profile?", isPresented: removeBinding) {
            Button("Remove Profile", role: .destructive) {
                if let profile = model.pendingRemoveProfile {
                    model.removeProfileFromList(profile)
                    model.pendingRemoveProfile = nil
                }
            }
            Button("Cancel", role: .cancel) {
                model.pendingRemoveProfile = nil
            }
        } message: {
            Text("AgentDock will forget this profile, but its local data will remain on disk and can be restored later.")
        }
        .alert("Permanently Delete Profile Data?", isPresented: deleteBinding) {
            Button("Delete Data", role: .destructive) {
                if let profile = model.pendingDeleteProfile {
                    model.deleteProfileData(profile)
                }
            }
            Button("Cancel", role: .cancel) {
                model.pendingDeleteProfile = nil
            }
        } message: {
            Text("This permanently removes the profile's managed local sessions, credentials, settings, and shortcut. This cannot be undone.")
        }
        .onAppear {
            model.refreshChats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentDockFocusSearch)) { _ in
            searchFocused = true
        }
        .onChange(of: model.detailTab) { _, tab in
            let surface: AnalyticsSurface = switch tab {
            case .overview: .overview
            case .chats: .chats
            case .advanced: .advanced
            }
            ProductAnalytics.shared.capture(AnalyticsEvent(
                .navigation,
                [.action(.viewed), .surface(surface)]
            ))
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Text("AgentDock")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 8)

            searchField
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    providerSection(.codex)
                    providerSection(.claude)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }

            Divider()
                .overlay(AgentDockPalette.divider)

            HStack {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .frame(width: 28, height: 28)
                        .background(
                            showsSettings ? AgentDockPalette.blue.opacity(0.72) : .clear,
                            in: .rect(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings")
                .accessibilityLabel("Settings")
                .accessibilityHint("Shows AgentDock settings")

                Spacer(minLength: 0)

                if updater.presentation.isVisible {
                    Button {
                        updater.installAvailableUpdate()
                    } label: {
                        HStack(spacing: 6) {
                            if updater.presentation.showsProgress {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text(updater.presentation.buttonTitle)
                                .lineLimit(1)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(AgentDockPalette.blue, in: .rect(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(updater.presentation.showsProgress)
                    .help(updateButtonHelp)
                    .accessibilityLabel(updateButtonAccessibilityLabel)
                }
            }
            .foregroundStyle(.secondary)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 48)
        }
    }

    private var updateButtonHelp: String {
        guard let version = updater.presentation.version else { return "Install update" }
        return "Install AgentDock \(version)"
    }

    private var updateButtonAccessibilityLabel: String {
        guard let version = updater.presentation.version else {
            return updater.presentation.buttonTitle
        }
        return "\(updater.presentation.buttonTitle) AgentDock \(version)"
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search profiles", text: $profileSearch)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit(selectFirstSearchResult)
            Text("⌘F")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(.white.opacity(0.04), in: .rect(cornerRadius: 5))
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .agentDockGlassControl()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func providerSection(_ product: DesktopProduct) -> some View {
        let profiles = filteredProfiles(for: product)
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(title: product == .codex ? "Codex" : "Claude Desktop")
                .padding(.horizontal, 10)
                .padding(.top, 6)

            Button {
                showsSettings = false
                model.selectOfficial(product)
            } label: {
                OfficialSidebarRow(
                    product: product,
                    isSelected: !showsSettings && model.sidebarSelection == .official(product)
                )
            }
            .buttonStyle(.plain)

            ForEach(profiles) { profile in
                Button {
                    showsSettings = false
                    model.selectProfile(profile.id)
                } label: {
                    ProfileSidebarRow(
                        profile: profile,
                        isSelected: !showsSettings && model.selectedProfileID == profile.id
                    )
                }
                .buttonStyle(.plain)
            }

            if profiles.isEmpty, !profileSearch.isEmpty {
                Text("No matching profiles")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    private var detail: some View {
        Group {
            if showsSettings {
                SettingsView(presentation: .embedded)
            } else {
                VStack(spacing: 0) {
                    detailToolbar
                    Divider()
                        .overlay(AgentDockPalette.divider)
                    Group {
                        switch model.detailTab {
                        case .overview:
                            OverviewView()
                        case .chats:
                            ChatsView()
                        case .advanced:
                            AdvancedView()
                        }
                    }
                }
            }
        }
        .background(AgentDockBackground())
    }

    private var detailToolbar: some View {
        ZStack {
            if model.selectedProfile != nil || model.selectedOfficialProduct != nil {
                Picker("Profile Section", selection: $model.detailTab) {
                    ForEach(visibleDetailTabs) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: visibleDetailTabs.count == 3 ? 300 : 170)
            }

            HStack {
                Spacer()

                Button {
                    model.showAddProfile = true
                } label: {
                    Label("Add Profile", systemImage: "plus")
                        .font(.system(size: 13))
                }
                .agentDockToolbarAction()
                .keyboardShortcut("n", modifiers: .command)

                Button(action: refreshContent) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 14, height: 14)
                }
                .agentDockToolbarAction()
                .help("Refresh profile activity and chats")
                .accessibilityLabel("Refresh")

                Menu {
                    Button("Restore Profile…") {
                        model.restoreProfile()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    private var visibleDetailTabs: [AgentDockDetailTab] {
        AgentDockDetailTab.availableTabs(hasManagedProfile: model.selectedProfile != nil)
    }

    private func filteredProfiles(for product: DesktopProduct) -> [CodexProfile] {
        let productProfiles = model.profiles.filter { $0.product == product }
        guard !profileSearch.isEmpty else { return productProfiles }
        return productProfiles.filter {
            $0.name.localizedCaseInsensitiveContains(profileSearch)
                || $0.slug.localizedCaseInsensitiveContains(profileSearch)
        }
    }

    private func selectFirstSearchResult() {
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .navigation,
            [.action(.searched), .surface(.sidebar)]
        ))
        let first = DesktopProduct.allCases
            .flatMap(filteredProfiles)
            .first
        if let first {
            showsSettings = false
            model.selectProfile(first.id)
        }
    }

    private func openSettings() {
        showsSettings = true
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .navigation,
            [.action(.viewed), .surface(.settingsGeneral)]
        ))
    }

    private func refreshContent() {
        ProductAnalytics.shared.capture(AnalyticsEvent(
            .refresh,
            [
                .action(.manualRefresh),
                .surface(selectedDetailAnalyticsSurface),
                .trigger(.user),
                .countBucket(.init(model.profiles.count))
            ]
        ))
        model.refreshStats()
        model.refreshChats()
    }

    private var selectedDetailAnalyticsSurface: AnalyticsSurface {
        switch model.detailTab {
        case .overview: .overview
        case .chats: .chats
        case .advanced: .advanced
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.preferences.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil && !model.showAddProfile },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var removeBinding: Binding<Bool> {
        Binding(
            get: { model.pendingRemoveProfile != nil },
            set: { if !$0 { model.pendingRemoveProfile = nil } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { model.pendingDeleteProfile != nil },
            set: { if !$0 { model.pendingDeleteProfile = nil } }
        )
    }

    private var analyticsConsentBinding: Binding<Bool> {
        Binding(
            get: { model.analyticsConsent == .undecided },
            set: { _ in }
        )
    }
}

private struct OfficialSidebarRow: View {
    @EnvironmentObject private var model: CodexerModel
    let product: DesktopProduct
    let isSelected: Bool

    var body: some View {
        let running = model.stockInstanceStatuses[product]?.isRunning == true
        HStack(spacing: 9) {
            ProviderIconView(product: product, appURL: model.appURL(for: product), size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Official \(product.displayName)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if model.preferences.showStatusInProfileList {
                        StatusDot(isRunning: running, size: 6)
                    }
                    Text(product.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(isSelected ? AgentDockPalette.blue.opacity(0.72) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityValue(running ? "Running" : "Stopped")
    }
}

private struct ProfileSidebarRow: View {
    @EnvironmentObject private var model: CodexerModel
    let profile: CodexProfile
    let isSelected: Bool

    var body: some View {
        let running = model.instanceStatus(for: profile).isRunning
        HStack(spacing: 9) {
            ProfileIconView(profile: profile, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if model.preferences.showStatusInProfileList {
                        StatusDot(isRunning: running, size: 6)
                    }
                    Text(profile.slug)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(isSelected ? AgentDockPalette.blue.opacity(0.72) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityValue(running ? "Running" : "Stopped")
    }
}

extension Notification.Name {
    static let agentDockFocusSearch = Notification.Name("AgentDock.focusSearch")
}
