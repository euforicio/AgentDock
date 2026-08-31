# Release Operations

## Local Packaging

Build and package an ad-hoc signed app:

```bash
./script/build_app.sh
./script/package_app.sh
```

Outputs:

```text
dist/AgentDock-<version>.zip
dist/AgentDock-<version>.dmg
```

The build script embeds the pinned Sparkle framework with its updater and XPC
services, signs every nested component before the outer app, and verifies the
result. The package script verifies the app structure, rejects filesystem
metadata sidecars, mounts the DMG read-only, scans it for build-machine paths,
and runs DMG integrity verification. The ZIP contains `AgentDock.app` at its
root, as required by Sparkle's archive extractor. An ad-hoc local build has no
Sparkle public key and keeps update checks disabled.

It also has no PostHog configuration, so product analytics cannot leave the
process. Production analytics require the two repository variables described
in [Product analytics](analytics.md). Configure them only after reviewing the
project region, IP capture, person profiles, access, and retention. The build
accepts only a public `phc_` token and an official US or EU ingestion host.

## Continuous Integration and Tag-Only Releases

`.github/workflows/ci.yml` validates pull requests and every push to `main`. It
runs the root and vendored test suites, the repository privacy audit, and an
ad-hoc build/package cycle. `.github/workflows/release.yml` remains tag-only; it
has no branch, pull-request, schedule, or manual-dispatch trigger. Equivalent
local validation is:

```bash
swift test
swift test --package-path Vendor/streamdown-swift
./script/audit_privacy.sh
./script/build_app.sh
./script/package_app.sh
```

The tag workflow:

1. serializes all stable releases, validates `vMAJOR.MINOR.PATCH`, requires the
   tag commit to be on `origin/main`, rejects version rollback against tags and
   the public appcast, and runs both test suites;
2. builds with a monotonic numeric `CFBundleVersion` derived from the semantic
   version;
3. signs Sparkle's nested components and AgentDock with Developer ID and the
   hardened runtime;
4. notarizes, staples, and verifies the app and DMG with Gatekeeper;
5. publishes the ZIP, DMG, and checksums to the immutable GitHub Release;
6. downloads the public ZIP and byte-compares it with the notarized workflow
   artifact before generating an Ed25519-signed appcast;
7. pushes `appcast.xml` to `gh-pages` only after every earlier gate succeeds;
8. polls the public Pages URL until its bytes exactly match the generated feed,
   then verifies its Ed25519 signature again.

Clients use `https://euforicio.github.io/AgentDock/appcast.xml`. Configure
GitHub Pages to publish from the root of the `gh-pages` branch before the first
Sparkle-enabled release.

The `Euforicio` organization must also allow **Read and write permissions** for
GitHub Actions workflow tokens under **Organization Settings → Actions →
General → Workflow permissions**. The workflow narrows that access to
`contents: write` only for the release and appcast publication jobs. A
repository-level write setting cannot override an organization policy that
caps `GITHUB_TOKEN` at read-only; in that state the signed build still succeeds,
but GitHub Release creation fails with `Resource not accessible by integration`
and the appcast is intentionally not published.

The release action intentionally omits `target_commitish`: the `v*` tag already
identifies the exact release commit. Supplying a target commit that changes a
workflow relative to the current default branch makes GitHub require workflow
write access, which the built-in `GITHUB_TOKEN` cannot receive. When diagnosing
a release API 403, confirm that the tag points at the intended commit and do not
work around this boundary with a broad personal access token.

## One-Time Sparkle Key Setup

The repository does not contain a release key. A release operator must create
one long-lived key once using the `generate_keys` binary from the pinned
Sparkle 2.9.6 distribution. Use a distinct Keychain account for AgentDock:

```bash
sparkle_bin='.build/artifacts/sparkle/Sparkle/bin'
"$sparkle_bin/generate_keys" --account dev.euforic.agentdock
private_key_file="$(mktemp -t agentdock-sparkle-key)"
"$sparkle_bin/generate_keys" --account dev.euforic.agentdock -x "$private_key_file"
gh secret set SPARKLE_PRIVATE_ED_KEY \
  --repo euforicio/AgentDock \
  --env release \
  < "$private_key_file"
gh variable set SPARKLE_PUBLIC_ED_KEY \
  --repo euforicio/AgentDock \
  --body "$("$sparkle_bin/generate_keys" --account dev.euforic.agentdock -p)"
rm -P "$private_key_file"
```

Create and protect the `release` GitHub environment before these commands.
Require an appropriate reviewer and restrict deployment branches/tags according
to the repository's release policy. Back up the private key in an approved
secret store; losing it prevents existing clients from trusting future updates.
Never rotate or replace it casually.

The protected `release` environment also gates the Developer ID, notarization,
and appcast signing jobs. Store all of these secrets in that environment:

- `DEVELOPER_ID_CERTIFICATE_PEM_BASE64`
- `DEVELOPER_ID_PRIVATE_KEY_PEM_BASE64`
- `APPLE_NOTARY_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`

## Publish a Release

After the key, environment, and Pages source are configured, create an immutable
version tag:

```bash
git tag v0.2.0
git push origin v0.2.0
```

There is intentionally no manual Actions release button. Do not move a
published tag after users have downloaded its assets. Issue a new patch version
for corrections.

Pre-Sparkle installations cannot discover the appcast. Users of those builds
must install the first Sparkle-enabled release manually from GitHub one final
time; subsequent releases update automatically according to their settings.

## Verify a Download

Download all three release files into the same directory, then run:

```bash
sed 's#  dist/#  #' AgentDock-<version>.sha256 | shasum -a 256 -c -
xcrun stapler validate AgentDock-<version>.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=4 AgentDock-<version>.dmg
hdiutil verify AgentDock-<version>.dmg
curl --fail --silent --show-error \
  https://euforicio.github.io/AgentDock/appcast.xml \
  | xmllint --noout -
```

## Rollback

GitHub Releases are immutable historical records once downloaded. If a release
is defective, document the issue, fix `main`, and publish a new patch release.
Do not silently replace trusted artifacts or move a published tag. Because the
appcast is published last, a failed build, notarization, release upload, or
appcast-signing job leaves clients on the previous valid feed.
