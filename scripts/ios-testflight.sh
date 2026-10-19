#!/usr/bin/env bash
#
# Archive Voteaxis for TestFlight / App Store Connect and upload.
#
# iOS IPA already targets iPhone + iPad (TARGETED_DEVICE_FAMILY = 1,2).
# There is no separate "iPadOS IPA" — one upload covers both.
#
# Prerequisites:
#   App Store Connect API Key (headless / recommended):
#     export APP_STORE_CONNECT_API_KEY_ID=...
#     export APP_STORE_CONNECT_API_ISSUER_ID=...
#     export APP_STORE_CONNECT_API_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXX.p8
#   Falls back to a signed-in Xcode account (Xcode → Settings → Accounts) if unset.
#
# Uploads go through `xcodebuild -exportArchive` with a `destination: upload`
# ExportOptions.plist, authenticated via the App Store Connect API key above
# (-authenticationKeyPath/-ID/-IssuerID). This replaces the deprecated
# `xcrun altool --upload-app`.
#
# Usage:
#   ./scripts/ios-testflight.sh                   # iOS/iPad IPA → TestFlight
#   ./scripts/ios-testflight.sh --bump            # Bump build number first
#   ./scripts/ios-testflight.sh --archive-only    # Build/export without uploading
#

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOBILE="$ROOT/mobile"
cd "$ROOT"

# Load .env if present
if [[ -f "$ROOT/.env" ]]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    # Only real NAME=value lines are exported. A multi-line value pasted into
    # .env (a .p8 is the known offender) arrives as loose lines that are not
    # assignments — exporting those fails with "invalid option", which buries
    # the error that actually explains the problem.
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    value="${line#*=}"
    value="${value%$'\r'}"
    if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    export "$key=$value"
  done < "$ROOT/.env"
fi

# App Store Connect auth. The API key is three things: a key id, an issuer id,
# and key material. The material can arrive as a path (developer machine), as
# the key itself (CI: APP_STORE_CONNECT_API_KEY — a GitHub secret survives the
# machine boundary, a path does not), or sit in Apple's conventional
# ~/.appstoreconnect/private_keys location. scripts/lib/asc-auth.sh normalises
# all three into ASC_KEY_PATH; asc_cleanup removes any temp copy on exit.
source "$ROOT/scripts/lib/asc-auth.sh"
trap asc_cleanup EXIT

archive_only=false
bump_version=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive-only) archive_only=true; shift ;;
    --bump) bump_version=true; shift ;;
    --ios|--ipados|--iphone) shift ;;
    -h|--help)
      sed -n '2,29p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if $bump_version; then
  node "$ROOT/scripts/native-versions.js" --bump
else
  # Keep Generated.xcconfig / local.properties aligned with pubspec even
  # when not bumping — stale FLUTTER_BUILD_NUMBER has shipped wrong builds.
  node "$ROOT/scripts/native-versions.js" --sync
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "❌ Xcode CLI tools not found. Please install Xcode." >&2
  exit 1
fi

# Shared Flutter dart-defines for release builds.
collect_build_args() {
  build_args=(--release)

  # Obfuscate the Dart AOT snapshot — the scoring, envelope crypto, and API
  # clients all live in it. Archive the symbols dir per release — it's
  # required to symbolicate obfuscated crash traces.
  local symbols_dir="$MOBILE/build/symbols/ios"
  mkdir -p "$symbols_dir"
  build_args+=(--obfuscate --split-debug-info="$symbols_dir")
  echo "   + obfuscation (symbols: $symbols_dir — archive this, needed to symbolicate crashes)"

  # The app's API/site origins are compile-time dart-defines with production
  # defaults (mobile/lib/config.dart), so nothing extra is needed for a store
  # build. VOTEAXIS_POLITICIANS_KEY stays unset — roster access for the app is
  # meant to be open; the compile-time key exists for tightening later.
}

# Uploads an .xcarchive straight to App Store Connect via a second
# `xcodebuild -exportArchive` pass (destination: upload in the plist),
# authenticated with the App Store Connect API key. This is Apple's
# replacement for `xcrun altool --upload-app`.
upload_to_app_store_connect() {
  local archive_path="$1"
  local upload_plist="$2"
  local upload_export_dir="$3"
  local label="$4" # e.g. "iOS/iPadOS IPA"

  asc_resolve_auth

  rm -rf "$upload_export_dir"
  mkdir -p "$upload_export_dir"

  if asc_auth_configured; then
    echo "🔹 Uploading to App Store Connect via API Key ($ASC_KEY_ID, source: $ASC_KEY_SOURCE)..."
  else
    echo ""
    echo "⚠️  App Store Connect API key not fully set — falling back to signed-in Xcode account."
    echo "   For CI uploads, pass the key as a value:"
    echo "     APP_STORE_CONNECT_API_KEY=<contents of AuthKey_XXXX.p8>"
    echo "   Locally, a path is fine: APP_STORE_CONNECT_API_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXX.p8"
    echo "   Either way also needs APP_STORE_CONNECT_API_KEY_ID and APP_STORE_CONNECT_API_ISSUER_ID."
  fi

  if xcodebuild -exportArchive \
      -archivePath "$archive_path" \
      -exportOptionsPlist "$upload_plist" \
      -exportPath "$upload_export_dir" \
      -allowProvisioningUpdates \
      "${ASC_AUTH_ARGS[@]+"${ASC_AUTH_ARGS[@]}"}"; then
    echo "🎉 SUCCESS: $label uploaded to App Store Connect / TestFlight!"
    return 0
  fi

  echo ""
  echo "❌ $label upload to App Store Connect failed." >&2
  echo "ℹ️  Archive available at: $archive_path" >&2
  echo "   You can upload manually via Xcode Organizer or Transporter.app." >&2
  return 1
}

build_and_upload_ios() {
  echo ""
  echo "🔹 Building iOS Release (iPhone + iPadOS) with Flutter..."
  echo "   (One IPA covers iPhone and iPad — TARGETED_DEVICE_FAMILY=1,2)"
  collect_build_args

  local ARCHIVE_PATH="$MOBILE/build/ios/archive/Runner.xcarchive"

  # API-key route — the only shape that reaches CI. `flutter build ipa` runs
  # `xcodebuild archive` internally and cannot pass it
  # -authenticationKeyPath/-ID/-IssuerID, and a runner has no signed-in Xcode
  # account for -allowProvisioningUpdates to fall back on. So the archive is
  # run by hand with the auth flags, then -exportArchive (destination: upload)
  # pushes the archive straight to App Store Connect. `flutter build ios
  # --no-codesign` runs first so Generated.xcconfig carries DART_DEFINES into
  # the archive's build phase.
  asc_resolve_auth
  if asc_auth_configured; then
    echo "🔹 Archiving iOS Runner with App Store Connect API auth..."
    (cd "$MOBILE" && flutter build ios "${build_args[@]}" --no-codesign)
    rm -rf "$ARCHIVE_PATH"
    mkdir -p "$(dirname "$ARCHIVE_PATH")"
    xcodebuild \
      -workspace "$MOBILE/ios/Runner.xcworkspace" \
      -scheme Runner \
      -configuration Release \
      -destination 'generic/platform=iOS' \
      -archivePath "$ARCHIVE_PATH" \
      DEVELOPMENT_TEAM=365KR8NF53 \
      CODE_SIGN_STYLE=Automatic \
      -allowProvisioningUpdates \
      "${ASC_AUTH_ARGS[@]+"${ASC_AUTH_ARGS[@]}"}" \
      archive

    if $archive_only; then
      echo "✓ Archive mode: Skipping iOS upload."
      echo "  Archive at: $ARCHIVE_PATH"
      return 0
    fi
    if ! upload_to_app_store_connect "$ARCHIVE_PATH" "$MOBILE/ios/ExportOptionsUpload.plist" "$MOBILE/build/ios/upload" "Voteaxis iOS/iPadOS IPA"; then
      exit 1
    fi
    return 0
  fi

  # Local route — signed-in Xcode account; `flutter build ipa` archives,
  # exports, and signs in one pass.
  (cd "$MOBILE" && flutter build ipa "${build_args[@]}" --export-options-plist="$MOBILE/ios/ExportOptions.plist")

  local IPA_PATH=""
  local FOUND_IPA
  FOUND_IPA="$(find "$MOBILE/build/ios/ipa" -name "*.ipa" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$FOUND_IPA" ]]; then
    IPA_PATH="$FOUND_IPA"
  else
    echo "❌ IPA not found in mobile/build/ios/ipa/" >&2
    exit 1
  fi

  local IPA_SIZE
  IPA_SIZE="$(du -h "$IPA_PATH" | cut -f1)"
  echo "✅ Signed IPA generated at: $IPA_PATH ($IPA_SIZE)"

  if $archive_only; then
    echo "✓ Archive mode: Skipping iOS upload."
    echo "  You can upload manually via Transporter.app or Xcode Organizer."
    return 0
  fi

  if [[ ! -d "$ARCHIVE_PATH" ]]; then
    echo "❌ Archive not found at $ARCHIVE_PATH" >&2
    exit 1
  fi

  if ! upload_to_app_store_connect "$ARCHIVE_PATH" "$MOBILE/ios/ExportOptionsUpload.plist" "$MOBILE/build/ios/upload" "Voteaxis iOS/iPadOS IPA"; then
    exit 1
  fi
}

build_and_upload_ios

echo ""
echo "👉 App Store Connect: https://appstoreconnect.apple.com/apps"
