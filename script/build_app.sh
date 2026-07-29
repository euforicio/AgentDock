#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${AGENTDOCK_APP_NAME:-AgentDock}"
BUNDLE_ID="${AGENTDOCK_BUNDLE_ID:-dev.euforic.agentdock}"
PRODUCT_BINARY_NAME="AgentDock"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${AGENTDOCK_DIST_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_LICENSES="$APP_RESOURCES/Licenses"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

VERSION="${AGENTDOCK_VERSION:-${CODEXER_VERSION:-}}"
if [[ -z "$VERSION" && "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  VERSION="${GITHUB_REF_NAME#v}"
fi
VERSION="${VERSION:-0.1.1}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: AGENTDOCK_VERSION must use MAJOR.MINOR.PATCH format" >&2
  exit 1
fi
BUILD_NUMBER="${AGENTDOCK_BUILD_NUMBER:-${CODEXER_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}}"
SIGNING_IDENTITY="${AGENTDOCK_SIGNING_IDENTITY:-${CODEXER_SIGNING_IDENTITY:--}}"
SIGNING_KEYCHAIN="${AGENTDOCK_SIGNING_KEYCHAIN:-${CODEXER_SIGNING_KEYCHAIN:-}}"

SOURCE_PREFIX_MAP="$ROOT_DIR=/workspace/AgentDock"
BUILD_ARGUMENTS=(
  -c release
  -Xswiftc -debug-prefix-map
  -Xswiftc "$SOURCE_PREFIX_MAP"
  -Xswiftc -file-prefix-map
  -Xswiftc "$SOURCE_PREFIX_MAP"
  -Xcc "-fdebug-prefix-map=$SOURCE_PREFIX_MAP"
  -Xcc "-ffile-prefix-map=$SOURCE_PREFIX_MAP"
)

swift build "${BUILD_ARGUMENTS[@]}"
BUILD_DIR="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$PRODUCT_BINARY_NAME"
HELPER_BINARY="$BUILD_DIR/AgentDockShortcutLauncher"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_LICENSES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$HELPER_BINARY" "$APP_RESOURCES/AgentDockShortcutLauncher"
cp "$ROOT_DIR/LICENSE" "$APP_RESOURCES/LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
cp "$ROOT_DIR/Vendor/streamdown-swift/LICENSE" "$APP_LICENSES/Streamdown-FSL-1.1-MIT.txt"
cp "$ROOT_DIR/.build/checkouts/MarkdownView/LICENSE" "$APP_LICENSES/MarkdownView-MIT.txt"
cp "$ROOT_DIR/.build/checkouts/swift-markdown/LICENSE.txt" "$APP_LICENSES/swift-markdown-Apache-2.0.txt"
cp "$ROOT_DIR/.build/checkouts/swift-markdown/NOTICE.txt" "$APP_LICENSES/swift-markdown-NOTICE.txt"
cp "$ROOT_DIR/.build/checkouts/Highlightr/LICENSE" "$APP_LICENSES/Highlightr-MIT.txt"
cp "$ROOT_DIR/.build/checkouts/Highlightr/src/assets/highlighter/LICENSE" "$APP_LICENSES/highlight.js-BSD-3-Clause.txt"
cp "$ROOT_DIR/.build/checkouts/RichText/LICENSE" "$APP_LICENSES/RichText-MIT.txt"
cp "$ROOT_DIR/.build/checkouts/swift-cmark/COPYING" "$APP_LICENSES/swift-cmark-COPYING.txt"
chmod 0644 "$APP_RESOURCES/LICENSE.txt" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md" "$APP_LICENSES"/*.txt
if [[ -f "$ROOT_DIR/Assets/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Assets/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi
chmod +x "$APP_BINARY"
chmod +x "$APP_RESOURCES/AgentDockShortcutLauncher"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --sign - "$APP_RESOURCES/AgentDockShortcutLauncher"
  /usr/bin/codesign --force --sign - "$APP_BUNDLE"
else
  SIGNING_ARGUMENTS=(
    --force
    --options runtime
    --timestamp
    --sign "$SIGNING_IDENTITY"
  )
  if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    SIGNING_ARGUMENTS+=(--keychain "$SIGNING_KEYCHAIN")
  fi
  /usr/bin/codesign "${SIGNING_ARGUMENTS[@]}" "$APP_RESOURCES/AgentDockShortcutLauncher"
  /usr/bin/codesign "${SIGNING_ARGUMENTS[@]}" "$APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
