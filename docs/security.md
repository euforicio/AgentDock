# Security and Privacy

## Trust Model

AgentDock coordinates local provider applications. It does not make an
untrusted provider process safe and is not an operating-system sandbox.

Security-sensitive operations validate:

- expected provider bundle identifiers and publisher signing teams;
- code signatures and executable paths;
- exact managed profile roots and ownership markers;
- process ancestry, PIDs, and profile arguments;
- path containment and symlink rejection;
- bounded file counts, bytes, subprocess output, and transcript pages.

If those checks fail, managed launch, focus, close, restore, delete, or
transcript reads fail closed.

These boundaries are implemented in
[DesktopAppRegistry.swift](../Sources/CodexerCore/DesktopAppRegistry.swift),
[DesktopInstanceController.swift](../Sources/CodexerCore/DesktopInstanceController.swift),
[ProfileStore.swift](../Sources/CodexerCore/ProfileStore.swift), and
[LocalChatSession.swift](../Sources/CodexerCore/LocalChatSession.swift).

## Shared Host Resources

Managed profiles retain access to normal user resources, including:

- files and project directories;
- shell environment and developer tools;
- network;
- Keychain;
- Git and SSH configuration;
- macOS permissions and provider updater state.

Use separate macOS accounts or stronger operating-system isolation when those
resources must not be shared.

## Local Data

AgentDock stores profile metadata and bounded chat indexes under
`~/Library/Application Support/AgentDock/`. New shortcuts live under
`~/Applications/AgentDock/`.

Chat indexes contain bounded titles, previews, timestamps, provider metadata,
and relative source paths. They do not contain full transcript bodies, tool
output, or absolute working directories. Transcript bodies are read on demand
from validated supported local sources.

AgentDock does not provide cloud synchronization, scrape browser cookies, or
read ordinary web-chat caches.

## Product Analytics

Analytics are a separate default-on, immediately revocable boundary implemented in
[`ProductAnalytics.swift`](../Sources/CodexerCore/ProductAnalytics.swift).
Only closed typed events can be batched to the configured regional PostHog
endpoint. Events never carry source content or local identifiers; GeoIP and
person-profile processing are disabled, and queues exist only in bounded
memory. Explicit opt-outs persist across upgrades and clear the queue and
random identifier. The public project
token is release configuration, not a credential; no private PostHog key
belongs in the app. See the [complete catalog](analytics.md).

## Repository and Release Hygiene

Do not commit:

- credentials, tokens, certificates, provisioning profiles, or environment
  files;
- provider profiles, chats, transcript exports, logs, databases, crash reports,
  or generated indexes;
- screenshots containing real account, project, device, or session data;
- build products or notarization material.

The [release workflow](../.github/workflows/release.yml) uses ephemeral
credentials, removes temporary keychains and key files, rejects filesystem
metadata sidecars and build paths, and publishes checksums for the notarized
artifacts.

Sparkle updates require HTTPS, a Developer ID signature, notarization, and an
Ed25519 signature. The public verification key is embedded in AgentDock. The
private key exists only as the environment-protected
`SPARKLE_PRIVATE_ED_KEY` GitHub Actions secret and is streamed to Sparkle's
tool over standard input. Release assets are published before the signed
appcast, so a client cannot discover an enclosure that is not yet available.

## Reporting a Vulnerability

Follow the [security policy](../SECURITY.md). Use a private GitHub security
advisory instead of a public issue when a report could expose a vulnerability,
credential, private transcript, or local path.
