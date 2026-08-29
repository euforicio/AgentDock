# Interfaces and Contracts

AgentDock does not expose a network service or public HTTP API. Its stable
interfaces are Swift package products, local process contracts, persisted
formats, and release scripts.

## Swift Package Products

`Package.swift` declares:

- `AgentDock`: the macOS app executable.
- `AgentDockShortcutLauncher`: the generated shortcut helper.
- `TranscriptRendererShowcase`: the synthetic renderer showcase.
- `CodexerCore`: profile, process, scanner, and shortcut logic.
- `TranscriptRenderer`: provider-neutral transcript models and views.

The two library products are integration surfaces inside this repository. They
do not carry a semantic-versioning compatibility promise independent of the app.

## Provider Launch Contracts

Codex profiles use:

```text
CODEX_HOME=<profile>/CODEX_HOME
--user-data-dir=<profile>/ElectronUserData
```

Claude profiles use:

```text
CLAUDE_USER_DATA_DIR=<profile>/UserData
```

Claude launches proceed only when the installed signed app still exposes the
verified early environment-variable and `app.setPath` behavior. AgentDock does
not use a generic Electron profile flag for Claude.

## Persistent Formats

- `profiles.json`: AgentDock-owned profile metadata.
- Profile ownership markers: bind managed directories to persisted profiles.
- Shortcut configuration plist: binds a generated shortcut to one provider,
  profile root, and ownership identity.
- Chat indexes: versioned, bounded summary metadata with relative source paths.
- Analytics state: `undecided`, `denied`, or `granted` in UserDefaults. The
  analytics boundary promotes only `undecided` to the default `granted` state.
  A random installation UUID exists only while granted and is deleted on
  opt-out; an explicit `denied` state persists across launches and upgrades.

Readers validate containment, type, ownership, and size before using persisted
paths or provider records.

Claude activity and token summaries for official installations and managed
profiles are derived at runtime from validated local Cowork audit records and
are not a new persisted format. Both source types expose the same summary
contract, including model mix, token coverage, and the latest locally emitted
rate-limit event. Coverage prevents partially available token data from being
mistaken for complete usage, and rate-limit events remain advisory snapshots,
not a stable provider quota API.

## Build and Release Environment

The build scripts accept namespaced environment variables including:

- `AGENTDOCK_VERSION`
- `AGENTDOCK_BUILD_NUMBER`
- `AGENTDOCK_SIGNING_IDENTITY`
- `AGENTDOCK_SIGNING_KEYCHAIN`
- `AGENTDOCK_NOTARY_KEY_PATH`
- `AGENTDOCK_NOTARY_KEY_ID`
- `AGENTDOCK_NOTARY_ISSUER_ID`
- `AGENTDOCK_POSTHOG_PROJECT_TOKEN` (public `phc_` project token only)
- `AGENTDOCK_POSTHOG_HOST` (`https://us.i.posthog.com` or
  `https://eu.i.posthog.com`)

Notarization variables must be supplied together. Release credentials belong in
GitHub Actions secrets or an ephemeral local process environment, never in
tracked files.

## MCP Callback Configuration

Managed Codex profiles reserve a unique localhost callback port and retain
profile-local OAuth credential storage settings. AgentDock does not route the
shared provider URL scheme between simultaneous instances.

Compatibility validation runs the selected Codex bundle against the exact
profile config through an isolated temporary home. It does not load or refresh
the profile's account credentials, so expired authentication cannot be
misreported as an invalid config.
