# Development and Testing

## Prerequisites

- Apple silicon Mac
- macOS 26 or newer
- Swift 6.2 or newer
- Xcode command-line tools

The official provider apps are optional for normal tests. Installed-app and
live-lifecycle checks are explicitly opt in.

Package targets and dependency versions are defined in
[Package.swift](../Package.swift) and [Package.resolved](../Package.resolved).

## Build and Run

```bash
swift build
swift test
./script/build_and_run.sh
```

Use `./script/build_and_run.sh --verify` to build, launch, and verify that the
app process exists. Build products and packages are written under ignored
`.build/` and `dist/` directories.

## Test Suites

```bash
swift test
```

The package includes
[core tests](../Tests/CodexerCoreTests),
[app-model tests](../Tests/CodexerAppTests/CodexerModelTests.swift),
[transcript-renderer tests](../Tests/TranscriptRendererTests), and vendored
parser tests. Tests must use real repository-native behavior; do not add mocks
or stubs.

Installed-app checks:

```bash
AGENTDOCK_LIVE_LIFECYCLE=1 swift test \
  --filter CodexLauncherTests/testLiveProfileCanOpenAndCloseWithoutTouchingStockInstance

AGENTDOCK_INSTALLED_CLAUDE_TEST=1 swift test \
  --filter ClaudeDesktopTests/testInstalledClaudeSignatureAndStartupContract

AGENTDOCK_CLAUDE_LIVE_LIFECYCLE=1 swift test \
  --filter ClaudeDesktopTests/testLiveClaudeProfileCanOpenAndCloseWithoutTouchingStock
```

These checks can open installed provider applications or temporary managed
profiles. Run them only on a Mac where that interaction is expected.

## Change Expectations

- Keep provider-specific discovery and parsing in `CodexerCore`.
- Keep transcript presentation provider-neutral and capability-gated.
- Preserve stable event identities and exact source order.
- Bound file inventories, subprocess output, transcript pages, and layout work.
- Validate paths and signatures immediately before security-sensitive actions.
- Update README or focused docs with user-visible behavior and contract changes.
- Never commit profiles, chats, logs, databases, credentials, screenshots with
  real data, or build artifacts.

See [Contributing](../CONTRIBUTING.md) for the pull-request workflow.
Release builds use [build_app.sh](../script/build_app.sh) and
[package_app.sh](../script/package_app.sh).
