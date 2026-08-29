import CodexerCore
import SwiftUI

struct OverviewView: View {
  @EnvironmentObject private var model: CodexerModel

  var body: some View {
    Group {
      if let profile = model.selectedProfile {
        ProfileOverview(profile: profile)
      } else if let product = model.selectedOfficialProduct {
        OfficialOverview(product: product)
      } else {
        AgentDockEmptyState(
          title: "Choose a Profile",
          systemImage: "person.crop.square.stack",
          description: "Select a provider app or profile in the sidebar."
        )
      }
    }
  }
}

private struct ProfileOverview: View {
  @EnvironmentObject private var model: CodexerModel
  @State private var activityDestination: ActivityDestination?
  let profile: CodexProfile

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          header

          if profile.product == .codex {
            UsageLimitsCard(
              limits: model.rateLimits(for: profile), accent: Color(hex: profile.iconColor)
            )
            .padding(.top, 18)
          } else {
            ClaudeUsageCard(
              stats: model.stats(for: profile),
              loading: model.statsAreLoading(for: profile),
              accent: Color(hex: profile.iconColor)
            )
            .padding(.top, 18)
          }

          activity
            .padding(.top, 20)

          if profile.product == .claude,
             model.profiles.filter({ $0.product == .claude }).count > 1
          {
            ClaudeProfilesCard(selectedProfile: profile)
              .padding(.top, 16)
          }

          Button {
            model.detailTab = .advanced
          } label: {
            HStack(spacing: 12) {
              Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.secondary)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Advanced")
                  .font(.system(size: 14, weight: .medium))
                Text("Provider app, local data, shortcut, and profile state")
                  .font(.system(size: 12))
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .background {
            OverviewSurfaceCard(cornerRadius: 8)
          }
          .padding(.top, 16)
          .accessibilityHint("Shows advanced profile management")

          Spacer(minLength: 16)
          footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
      }
      .background(AgentDockPalette.graphite)
    }
    .sheet(item: $activityDestination) { destination in
      ActivityDetailSheet(profile: profile, destination: destination)
    }
  }

  private var header: some View {
    let status = model.instanceStatus(for: profile)
    return VStack(spacing: 0) {
      HStack(spacing: 16) {
        ProfileIconView(profile: profile, size: 54)

        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 7) {
            Text(profile.name)
              .font(.system(size: 24, weight: .semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
            Button {
              model.showEditProfile = true
            } label: {
              Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 25, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Edit Profile")
          }
          Text(profile.slug)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
          HStack(spacing: 10) {
            StatusDot(isRunning: status.isRunning, size: 8)
            Text(status.isRunning ? "Running" : "Stopped")
            Divider().frame(height: 14)
            Text(lastOpenedText)
              .lineLimit(1)
          }
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        }

        Spacer(minLength: 12)

        Button {
          model.launch(profile)
        } label: {
          Label(
            status.isRunning
              ? "Focus \(profile.product.displayName)" : "Open \(profile.product.displayName)",
            systemImage: status.isRunning ? "arrow.up.forward.app.fill" : "play.fill"
          )
        }
        .agentDockPrimaryAction()
        .controlSize(.regular)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(model.isBusy(profile))

        if status.isRunning {
          Button(role: .destructive) {
            model.close(profile)
          } label: {
            Image(systemName: "stop.fill")
          }
          .buttonStyle(.bordered)
          .controlSize(.regular)
          .help("Close this profile only")
          .disabled(model.isBusy(profile))
        }

        if model.isBusy(profile) {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Updating profile")
        }
      }
      .frame(minHeight: 58, alignment: .top)

      Divider()
        .overlay(AgentDockPalette.divider)
        .padding(.top, 14)
    }
  }

  private var activity: some View {
    let stats = model.stats(for: profile)
    let loading = model.statsAreLoading(for: profile)
    return VStack(alignment: .leading, spacing: 8) {
      SectionLabel(title: "Activity")
      VStack(spacing: 0) {
        ActivityRow(
          icon: "externaldrive",
          title: "Storage",
          value: loading
            ? "Loading…"
            : ByteCountFormatter.agentDock.string(fromByteCount: stats.dataBytes)
        ) {
          activityDestination = .storage
        }
        if profile.product == .codex {
          Divider().overlay(AgentDockPalette.divider).frame(height: 0)
          ActivityRow(
            icon: "doc.text",
            title: "Logs, last 7 days",
            value: loading
              ? "Loading…"
              : "\(stats.weeklyErrors) errors · \(stats.weeklyWarnings) warnings",
            valueColor: stats.weeklyErrors > 0
              ? .red : (stats.weeklyWarnings > 0 ? .orange : .secondary)
          ) {
            activityDestination = .logs
          }
          Divider().overlay(AgentDockPalette.divider).frame(height: 0)
          ActivityRow(
            icon: "waveform.path.ecg",
            title: "Latest local activity",
            value: loading
              ? "Loading…"
              : stats.lastActivityAt?.formatted(date: .abbreviated, time: .shortened)
                ?? "No activity yet"
          ) {
            activityDestination = .lastActivity
          }
          Divider().overlay(AgentDockPalette.divider).frame(height: 0)
          ActivityRow(
            icon: "archivebox",
            title: "Archived",
            value: loading ? "Loading…" : "\(stats.archivedSessions)"
          ) {
            activityDestination = .archived
          }
        } else {
          Divider().overlay(AgentDockPalette.divider).frame(height: 0)
          ActivityRow(
            icon: "text.bubble",
            title: "Local sessions",
            value: loading ? "Loading…" : stats.totalSessions.formatted()
          ) {
            activityDestination = .lastActivity
          }
          Divider().overlay(AgentDockPalette.divider).frame(height: 0)
          ActivityRow(
            icon: "waveform.path.ecg",
            title: "Latest local activity",
            value: loading
              ? "Loading…"
              : stats.lastActivityAt?.formatted(date: .abbreviated, time: .shortened)
                ?? "No activity yet"
          ) {
            activityDestination = .lastActivity
          }
        }
      }
      .background {
        OverviewSurfaceCard(cornerRadius: 8)
      }

      if profile.product == .claude {
        Label(
          "Token and activity totals come from this profile's local Cowork history. Limit status is the latest Claude-emitted signal, not a complete quota snapshot.",
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
      }

      ForEach(stats.errorMessages, id: \.self) { message in
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 10) {
      Text("AgentDock.app \(appVersion)")
      Circle().frame(width: 4, height: 4)
      Text("Stored locally")
      Circle().frame(width: 4, height: 4)
      Text(Date.now.formatted(date: .long, time: .omitted))
    }
    .font(.system(size: 11))
    .foregroundStyle(.tertiary)
    .frame(height: 30, alignment: .bottomLeading)
  }

  private var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }

  private var lastOpenedText: String {
    guard let date = profile.lastLaunchedAt else { return "Never opened" }
    return "Last opened \(date.formatted(date: .abbreviated, time: .shortened))"
  }
}

private struct OfficialOverview: View {
  @EnvironmentObject private var model: CodexerModel
  @State private var activityDestination: ActivityDestination?
  let product: DesktopProduct

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 14) {
          ProviderIconView(product: product, appURL: model.appURL(for: product), size: 54)
          VStack(alignment: .leading, spacing: 3) {
            Text("Official \(product.displayName)")
              .font(.system(size: 24, weight: .semibold))
            Text("Default installation")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button {
            model.openStock(product)
          } label: {
            Label("Open \(product.displayName)", systemImage: "play.fill")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.regular)
          .disabled(model.busyStockProducts.contains(product))
        }

        Divider().overlay(AgentDockPalette.divider)

        if product == .codex {
          UsageLimitsCard(limits: model.officialCodexRateLimits, accent: AgentDockPalette.blue)
          OfficialActivityCard(
            stats: model.officialCodexStats,
            loading: model.officialStatsLoading
          ) { destination in
            activityDestination = destination
          }
        } else {
          ClaudeUsageCard(
            stats: model.officialClaudeStats,
            loading: model.officialStatsLoading,
            accent: .orange
          )
          OfficialActivityCard(
            stats: model.officialClaudeStats,
            loading: model.officialStatsLoading
          ) { destination in
            activityDestination = destination
          }
          VStack(alignment: .leading, spacing: 6) {
            Label("Claude Desktop local boundary", systemImage: "lock.shield")
              .fontWeight(.medium)
            Text(
              "Managed profiles isolate Claude user data, logs, configuration, and encrypted payload files. Keychain services, permissions, updater state, filesystem, network, shell, Git, and SSH remain shared."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
          }
          .padding(12)
          .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
        }
      }
      .padding(22)
      .frame(maxWidth: 960, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .sheet(item: $activityDestination) { destination in
      ActivityDetailSheet(officialProduct: product, destination: destination)
    }
  }
}

private struct ClaudeUsageCard: View {
  let stats: ProfileStats
  let loading: Bool
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(title: "Claude Usage")
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          metric(title: "Sessions, 7 days", value: loading ? "Loading…" : stats.weeklySessions.formatted())
          Divider().overlay(AgentDockPalette.divider)
          metric(title: "Processed tokens, 7 days", value: loading ? "Loading…" : stats.weeklyTokens.formatted())
          Divider().overlay(AgentDockPalette.divider)
          metric(title: "Token coverage", value: loading ? "Loading…" : coverageText)
        }
        .frame(height: 72)

        Divider().overlay(AgentDockPalette.divider)

        usageLimitSignal

        if !stats.modelUsage.isEmpty {
          Divider().overlay(AgentDockPalette.divider)
          VStack(alignment: .leading, spacing: 8) {
            Text("Models")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(.secondary)
            ForEach(stats.modelUsage.prefix(3)) { model in
              HStack {
                Text(model.model)
                  .font(.system(size: 12, design: .monospaced))
                  .lineLimit(1)
                Spacer()
                Text("\(model.sessions) sessions · \(model.tokens.formatted()) tokens")
                  .font(.system(size: 11).monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
          .padding(12)
        }
      }
      .background { OverviewSurfaceCard(cornerRadius: 8) }
    }
  }

  private func metric(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 17, weight: .semibold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var usageLimitSignal: some View {
    if let signal = stats.latestUsageLimit {
      HStack(spacing: 12) {
        Image(systemName: signal.status == .rejected ? "exclamationmark.octagon.fill" : "gauge.with.dots.needle.50percent")
          .foregroundStyle(signal.status == .rejected ? .red : (signal.status == .warning ? .orange : accent))
          .frame(width: 28)
        VStack(alignment: .leading, spacing: 3) {
          Text(limitTitle(signal))
            .font(.system(size: 13, weight: .medium))
          Text(limitDetail(signal))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
        if let percent = signal.usedPercent {
          Text("\(Int(percent.rounded()))% used")
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .padding(12)
    } else {
      Label("No Claude limit signal has been emitted in the scanned local history.", systemImage: "gauge.open.with.lines.needle.33percent")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var coverageText: String {
    guard stats.totalSessions > 0 else { return "No sessions" }
    return "\(stats.tokenizedSessions) of \(stats.totalSessions)"
  }

  private func limitTitle(_ signal: UsageLimitSignal) -> String {
    let bucket = signal.bucket?
      .replacingOccurrences(of: "_", with: " ")
      .capitalized ?? "Usage"
    switch signal.status {
    case .allowed: return "\(bucket) allowed"
    case .warning: return "\(bucket) nearing limit"
    case .rejected: return "\(bucket) limit reached"
    }
  }

  private func limitDetail(_ signal: UsageLimitSignal) -> String {
    var parts = ["Observed \(signal.observedAt.formatted(date: .abbreviated, time: .shortened))"]
    if let reset = signal.resetsAt {
      parts.append("resets \(reset.formatted(date: .omitted, time: .shortened))")
    }
    if signal.isUsingOverage == true { parts.append("using overage") }
    return parts.joined(separator: " · ")
  }
}

private struct ClaudeProfilesCard: View {
  @EnvironmentObject private var model: CodexerModel
  let selectedProfile: CodexProfile

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(title: "Claude Profiles")
      VStack(spacing: 0) {
        ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
          Button {
            model.selectProfile(profile.id)
          } label: {
            HStack(spacing: 10) {
              ProfileIconView(profile: profile, size: 30)
              VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                  .font(.system(size: 13, weight: profile.id == selectedProfile.id ? .semibold : .regular))
                Text(summary(for: profile))
                  .font(.system(size: 11))
                  .foregroundStyle(.secondary)
              }
              Spacer()
              StatusDot(isRunning: model.instanceStatus(for: profile).isRunning, size: 7)
              Text(model.instanceStatus(for: profile).isRunning ? "Running" : "Stopped")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          if index < profiles.count - 1 {
            Divider().overlay(AgentDockPalette.divider)
          }
        }
      }
      .background { OverviewSurfaceCard(cornerRadius: 8) }
    }
  }

  private var profiles: [CodexProfile] {
    model.profiles.filter { $0.product == .claude }
  }

  private func summary(for profile: CodexProfile) -> String {
    let stats = model.stats(for: profile)
    if model.statsAreLoading(for: profile) { return "Loading local usage…" }
    return "\(stats.weeklySessions) sessions · \(stats.weeklyTokens.formatted()) tokens in 7 days"
  }
}

private struct UsageLimitsCard: View {
  let limits: ProfileRateLimits?
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(title: "Usage Limits")
      VStack(spacing: 0) {
        if let error = limits?.errorMessage {
          Label(error, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if limits == nil {
          HStack {
            ProgressView().controlSize(.small)
            Text("Loading Codex usage limits…")
              .foregroundStyle(.secondary)
            Spacer()
          }
          .padding(.vertical, 10)
        } else if let limits, limits.buckets.isEmpty {
          Text("No Codex usage-limit data is currently available.")
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          ForEach(Array((limits?.buckets ?? []).enumerated()), id: \.element.id) { index, bucket in
            VStack(spacing: 0) {
              if let primary = bucket.primary {
                LimitRow(
                  icon: "clock",
                  title: windowTitle(primary),
                  usage: primary,
                  accent: accent
                )
              }
              if let secondary = bucket.secondary {
                Divider().overlay(AgentDockPalette.divider)
                LimitRow(
                  icon: "calendar",
                  title: windowTitle(secondary),
                  usage: secondary,
                  accent: accent
                )
              }
              if index < (limits?.buckets.count ?? 0) - 1 {
                Divider().overlay(AgentDockPalette.divider)
              }
            }
          }
        }
      }
    }
  }

  private func windowTitle(_ usage: RateLimitWindowUsage) -> String {
    guard let minutes = usage.windowDurationMins else { return "Usage window" }
    if minutes == 10_080 { return "Weekly" }
    if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
    return "\(minutes)-minute"
  }
}

private struct LimitRow: View {
  let icon: String
  let title: String
  let usage: RateLimitWindowUsage
  let accent: Color

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 16))
        .foregroundStyle(.secondary)
        .frame(width: 34, height: 40)
        .background(.secondary.opacity(0.09), in: .rect(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 14, weight: .medium))
        Text(resetText)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(width: 190, alignment: .leading)

      ProgressView(value: min(max(usage.usedPercent, 0), 100), total: 100)
        .tint(usage.usedPercent >= 90 ? .red : accent)

      Text("\(Int(usage.usedPercent.rounded()))% used")
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 82, alignment: .trailing)
    }
    .frame(height: 54)
  }

  private var resetText: String {
    guard let date = usage.resetsAt else { return "Reset time unavailable" }
    return "Resets \(date.formatted(date: .abbreviated, time: .shortened))"
  }
}

private struct OfficialActivityCard: View {
  let stats: ProfileStats
  let loading: Bool
  let onSelect: (ActivityDestination) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(title: "Activity")
      VStack(spacing: 0) {
        ActivityRow(
          icon: "bubble.left.and.bubble.right",
          title: "Sessions",
          value: loading ? "Loading…" : "\(stats.totalSessions)"
        ) {
          onSelect(.sessions)
        }
        Divider().overlay(AgentDockPalette.divider)
        ActivityRow(
          icon: "externaldrive", title: "Storage",
          value: loading
            ? "Loading…"
            : ByteCountFormatter.agentDock.string(fromByteCount: stats.dataBytes)
        ) {
          onSelect(.storage)
        }
        Divider().overlay(AgentDockPalette.divider)
        ActivityRow(
          icon: "waveform.path.ecg", title: "Latest local activity",
          value: loading
            ? "Loading…"
            : stats.lastActivityAt?.formatted(date: .abbreviated, time: .shortened)
              ?? "No activity yet"
        ) {
          onSelect(.lastActivity)
        }
      }
    }
  }
}

private struct ActivityRow: View {
  let icon: String
  let title: String
  let value: String
  var valueColor: Color = .secondary
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 15))
          .foregroundStyle(.secondary)
          .frame(width: 24)
        Text(title)
          .font(.system(size: 13))
        Spacer()
        Text(value)
          .font(.system(size: 12))
          .foregroundStyle(valueColor)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 14)
      .frame(height: 46)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityHint("Shows \(title.lowercased()) details")
  }
}

private struct OverviewSurfaceCard: View {
  let cornerRadius: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(AgentDockPalette.panel.opacity(0.42))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(AgentDockPalette.divider.opacity(0.75), lineWidth: 1)
      }
  }
}
