# Data Flows

## Create and Launch a Profile

1. The UI requests profile creation through
   [`CodexerModel`](../Sources/Codexer/CodexerModel.swift).
2. [`ProfileStore`](../Sources/CodexerCore/ProfileStore.swift) allocates a provider-scoped slug, directory, ownership marker,
   and persisted profile record under a cross-process lock.
3. The selected launcher validates the official provider bundle and its signing
   identity.
4. Before a new Codex launch, AgentDock closes any provider-signed orphan helper
   whose live executable remains contained by that profile's `CODEX_HOME`.
5. AgentDock starts a new provider instance with the profile-specific local
   state contract.
6. Post-launch discovery verifies the returned process before the UI marks the
   profile as running.

Failed persistence or validation rolls back partial state where safe. A
destructive delete uses a separate confirmation and fails closed while the
profile is in use.

Removing a profile from the list preserves its ownership identity. Restoring
that managed directory reuses the verified marker identifier, so an existing
profile shortcut remains bound to the same profile.

## Focus and Close

1. [`DesktopInstanceController`](../Sources/CodexerCore/DesktopInstanceController.swift)
   finds candidates carrying the exact managed profile root.
2. AgentDock resolves and validates the signed main process and any
   provider-signed helper executable contained by the selected profile root.
3. Focus activates only that PID.
4. Close sends graceful termination only to verified processes for the selected
   profile, tracks captured descendants by stable process identity, and bounds
   the wait for cleanup.

The stock provider app and other managed profiles do not match the selected
profile path.

## Local Chat Indexing

1. [`LocalChatSession`](../Sources/CodexerCore/LocalChatSession.swift) inventories
   only supported provider metadata sources. Codex database rows accelerate
   metadata lookup but are merged with the bounded session-file inventory
   rather than treated as a complete list.
2. The scanner validates source roots, rejects symlinks, bounds file counts and
   bytes, and uses no-follow reads.
3. AgentDock writes a versioned profile-scoped summary index atomically with
   owner-only permissions.
4. The list presents bounded titles, previews, and source metadata.
5. Opening a chat reads a bounded transcript page and converts source events
   into the provider-neutral renderer model.
6. Unsupported source events render as bounded, content-free placeholders;
   malformed records remain visibly distinct.
7. Additional pages append in source order while stable IDs prevent duplicate
   rows and stale chat switches are suppressed.

For official and managed Claude sources, the same validated Cowork audit
sources also feed an in-memory usage summary. Assistant token records are
deduplicated by their message/request identity before aggregation, scans are
byte-bounded and cached by source size and modification time, and model totals
remain source-scoped. The overview uses the same usage and activity components
for both source types and lists the official installation beside managed
accounts for quick comparison and selection.
Claude `rate_limit_event` records contribute only their latest observed status,
bucket, reset time, and optional utilization. Missing utilization stays missing;
AgentDock does not carry an older percentage into a newer limit window.

Full transcript bodies and tool output are not stored in the summary index.
Malformed, partial, and unsupported events remain visible instead of silently
disappearing.

## Product Analytics

1. On first initialization, an undecided installation is enabled by default and
   receives a random UUID unrelated to local or provider data.
2. An explicit prior opt-out remains denied and capture exits without a payload,
   network request, or installation identifier.
3. Call sites submit closed enum events to the single core boundary.
4. The boundary validates properties, adds minimal platform context, disables
   GeoIP/person profiles, and holds at most 48 events in memory.
5. Up to twelve events are sent in a bounded HTTPS batch after at most five
   seconds. Failures are dropped without logs or persistent retries.
6. Opt-out synchronously purges pending events and deletes the UUID; re-enabling
   creates an unlinkable replacement.

No profile, provider-account, chat, transcript, session, filesystem, command,
configuration, raw error, log, or crash content enters this flow.

## Shortcut Installation

1. AgentDock validates the selected profile and official provider app.
2. [`ShortcutInstaller`](../Sources/CodexerCore/ShortcutInstaller.swift) creates a native helper bundle in a temporary sibling.
3. The shortcut configuration is bound to the profile ownership marker.
4. The completed shortcut atomically replaces the prior bundle under
   `~/Applications/AgentDock/`.

## Release Artifacts

1. A `vMAJOR.MINOR.PATCH` tag starts the only
   [release workflow](../.github/workflows/release.yml); branches, pull requests,
   schedules, and manual dispatches cannot start it.
2. The workflow runs the full Swift test suite.
3. A production app is built with hardened runtime and a Developer ID
   signature.
4. Sparkle.framework, its updater helper, and its XPC services are signed from
   the inside out before the outer app is signed.
5. The app and DMG are submitted to Apple notarization and stapled.
6. Gatekeeper, code-signature, DMG integrity, ZIP sidecar, and build-path privacy
   checks run before publication.
7. GitHub Releases receives the ZIP, DMG, and SHA-256 checksum file using
   [package_app.sh](../script/package_app.sh).
8. Only after the immutable release ZIP exists, Sparkle's `generate_appcast`
   signs an enclosure pointing at that tagged asset. The signed appcast is the
   final publication, on the `gh-pages` branch.

No release credential is stored in the repository or packaged artifact.
