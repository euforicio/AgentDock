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

The package script verifies the app structure, rejects filesystem metadata
sidecars, mounts the DMG read-only, scans it for build-machine paths, and runs
DMG integrity verification.

## Continuous Integration

`.github/workflows/release.yml` runs on pushes, pull requests, version tags, and
manual dispatches. Ordinary branch builds use ad-hoc signing. Tagged and manual
releases require Developer ID and notarization credentials stored as GitHub
Actions secrets.

The release gate verifies:

- full Swift tests;
- semantic release version;
- Developer ID signature and hardened runtime;
- app and DMG notarization tickets;
- Gatekeeper acceptance;
- ZIP and DMG integrity;
- absence of AppleDouble, `.DS_Store`, and filesystem-event sidecars;
- absence of mounted build-machine paths;
- SHA-256 checksums before publication.

## Publish a Release

Prefer the `Build and Release` manual workflow with a `MAJOR.MINOR.PATCH`
version. A matching version tag is also supported:

```bash
git tag v0.2.0
git push origin v0.2.0
```

Do not move a published tag after users have downloaded its assets. Issue a new
patch version for corrections.

## Verify a Download

Download all three files from one release into the same directory, then run:

```bash
sed 's#  dist/#  #' AgentDock-<version>.sha256 | shasum -a 256 -c -
xcrun stapler validate AgentDock-<version>.dmg
spctl --assess --type open --context context:primary-signature \
  --verbose=4 AgentDock-<version>.dmg
hdiutil verify AgentDock-<version>.dmg
```

The `sed` normalization is required by the current checksum format. Future
releases should write basename-only checksum entries.

## Rollback

GitHub Releases are immutable historical records once downloaded. If a release
is defective, mark it as a prerelease or document the issue, fix `main`, and
publish a new patch release. Do not silently replace trusted artifacts.
