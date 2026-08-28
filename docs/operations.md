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

## Tag-Only Release Workflow

`.github/workflows/release.yml` runs only when a `v*` tag is pushed. It has no
branch, pull-request, schedule, or manual-dispatch trigger. Ordinary development
validation remains local:

```bash
swift test
./script/build_app.sh
./script/package_app.sh
```

The tag workflow:

1. validates `vMAJOR.MINOR.PATCH` and runs the full test suite;
2. builds with a monotonic numeric `CFBundleVersion` derived from the semantic
   version;
3. signs Sparkle's nested components and AgentDock with Developer ID and the
   hardened runtime;
4. notarizes, staples, and verifies the app and DMG with Gatekeeper;
5. publishes the ZIP, DMG, and checksums to the immutable GitHub Release;
6. generates an Ed25519-signed appcast whose enclosure is the tagged GitHub
   Release ZIP;
7. pushes `appcast.xml` to `gh-pages` only after every earlier gate succeeds.

Clients use `https://euforicio.github.io/AgentDock/appcast.xml`. Configure
GitHub Pages to publish from the root of the `gh-pages` branch before the first
Sparkle-enabled release.

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

The environment also requires the existing Developer ID and notarization
secrets:

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
