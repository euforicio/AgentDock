# Data Flows

## Create and Launch a Profile

1. The UI requests profile creation through
   [`CodexerModel`](../Sources/Codexer/CodexerModel.swift).
2. [`ProfileStore`](../Sources/CodexerCore/ProfileStore.swift) allocates a provider-scoped slug, directory, ownership marker,
   and persisted profile record under a cross-process lock.
3. The selected launcher validates the official provider bundle and its signing
   identity.
4. AgentDock starts a new provider instance with the profile-specific local
   state contract.
5. Post-launch discovery verifies the returned process before the UI marks the
   profile as running.

Failed persistence or validation rolls back partial state where safe. A
destructive delete uses a separate confirmation and fails closed while the
profile is in use.

## Focus and Close

1. [`DesktopInstanceController`](../Sources/CodexerCore/DesktopInstanceController.swift)
   finds candidates carrying the exact managed profile root.
2. AgentDock resolves and validates the signed main process.
3. Focus activates only that PID.
4. Close sends graceful termination only to verified processes for the selected
   profile and bounds the wait for cleanup.

The stock provider app and other managed profiles do not match the selected
profile path.

## Local Chat Indexing

1. [`LocalChatSession`](../Sources/CodexerCore/LocalChatSession.swift) inventories only supported provider metadata sources.
2. The scanner validates source roots, rejects symlinks, bounds file counts and
   bytes, and uses no-follow reads.
3. AgentDock writes a versioned profile-scoped summary index atomically with
   owner-only permissions.
4. The list presents bounded titles, previews, and source metadata.
5. Opening a chat reads a bounded transcript page and converts source events
   into the provider-neutral renderer model.
6. Additional pages append in source order while stable IDs prevent duplicate
   rows and stale chat switches are suppressed.

Full transcript bodies and tool output are not stored in the summary index.
Malformed, partial, and unsupported events remain visible instead of silently
disappearing.

## Shortcut Installation

1. AgentDock validates the selected profile and official provider app.
2. [`ShortcutInstaller`](../Sources/CodexerCore/ShortcutInstaller.swift) creates a native helper bundle in a temporary sibling.
3. The shortcut configuration is bound to the profile ownership marker.
4. The completed shortcut atomically replaces the prior bundle under
   `~/Applications/AgentDock/`.

## Release Artifacts

1. The [release workflow](../.github/workflows/release.yml) runs the full Swift
   test suite.
2. A production app is built with hardened runtime and a Developer ID
   signature.
3. The app and DMG are submitted to Apple notarization and stapled.
4. Gatekeeper, code-signature, DMG integrity, ZIP sidecar, and build-path privacy
   checks run before publication.
5. GitHub Releases receives the ZIP, DMG, and SHA-256 checksum file using
   [package_app.sh](../script/package_app.sh).

No release credential is stored in the repository or packaged artifact.
