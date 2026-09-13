#!/usr/bin/env bash
# Boot a mobile emulator if needed, then flutter run.
# Usage: mobile-run.sh [ios|android]
set -euo pipefail

PLATFORM="${1:-ios}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOBILE="$ROOT/mobile"

device_id_for() {
  local platform="$1"
  flutter devices --machine 2>/dev/null |
    python3 -c "
import json, sys
platform = sys.argv[1]
devices = json.load(sys.stdin)
for d in devices:
    if d.get('targetPlatform') == platform and d.get('isSupported', True):
        print(d['id'])
        break
" "$platform"
}

wait_for_device() {
  local platform="$1"
  local label="$2"
  echo "Waiting for $label..."
  for _ in $(seq 1 90); do
    local id
    id="$(device_id_for "$platform" || true)"
    if [[ -n "${id:-}" ]]; then
      echo "Found $label ($id)"
      DEVICE_ID="$id"
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for $label." >&2
  flutter devices >&2 || true
  return 1
}

boot_ios() {
  DEVICE_ID="$(device_id_for ios || true)"
  if [[ -n "${DEVICE_ID:-}" ]]; then
    echo "iOS device already available ($DEVICE_ID)"
    return 0
  fi

  echo "Opening iOS Simulator..."
  open -a Simulator

  if ! xcrun simctl list devices | grep -q '(Booted)'; then
    local udid=""
    udid="$(
      xcrun simctl list devices available |
        grep -E 'iPhone 17 Pro \(' |
        head -1 |
        sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' || true
    )"
    if [[ -z "$udid" ]]; then
      udid="$(
        xcrun simctl list devices available |
          grep -E 'iPhone .* \(' |
          head -1 |
          sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' || true
      )"
    fi
    if [[ -n "$udid" ]]; then
      echo "Booting simulator $udid..."
      xcrun simctl boot "$udid" 2>/dev/null || true
    fi
  fi

  wait_for_device ios 'iOS Simulator'
}

boot_android() {
  DEVICE_ID="$(device_id_for android || true)"
  if [[ -n "${DEVICE_ID:-}" ]]; then
    echo "Android device already available ($DEVICE_ID)"
    return 0
  fi

  echo "Launching Android emulator..."
  local emu_id
  emu_id="$(
    flutter emulators 2>/dev/null |
      awk -F'•' 'NR>3 && /android/ {
        id=$1
        gsub(/^ +| +$/,"",id)
        if (id != "" && id != "Id") { print id; exit }
      }'
  )"
  if [[ -z "$emu_id" ]]; then
    echo "No Android emulator found. Create one in Android Studio (Device Manager)." >&2
    return 1
  fi

  flutter emulators --launch "$emu_id"
  wait_for_device android 'Android emulator'
}

DEVICE_ID=""
cd "$MOBILE"

# android/gradle.properties passes --enable-native-access to the Gradle *daemon*;
# the launcher JVM never sees it, so Android Studio's bundled JDK 25 warns that
# native-platform calls a restricted java.lang.System method — and a future JDK
# will block it outright rather than warn. GRADLE_OPTS is the only lever for the
# launcher.
export GRADLE_OPTS="${GRADLE_OPTS:-} --enable-native-access=ALL-UNNAMED"

# mobile/.env supplies dart-defines (see mobile/.env.example). Values already
# exported in the shell win over the file.
if [[ -f "$MOBILE/.env" ]]; then
  shell_api="${VOTEAXIS_API_URL:-}"
  shell_site="${VOTEAXIS_SITE_URL:-}"
  set -a
  # shellcheck disable=SC1091
  source "$MOBILE/.env"
  set +a
  if [[ -n "$shell_api" ]]; then VOTEAXIS_API_URL="$shell_api"; fi
  if [[ -n "$shell_site" ]]; then VOTEAXIS_SITE_URL="$shell_site"; fi
fi

DEFINE_ARGS=()
for var in VOTEAXIS_API_URL VOTEAXIS_SITE_URL; do
  value="$(eval "printf '%s' \"\${$var:-}\"")"
  if [[ -n "$value" ]]; then
    echo "Using $var=$value"
    DEFINE_ARGS+=(--dart-define="$var=$value")
  fi
done

case "$PLATFORM" in
  ios)
    boot_ios
    exec flutter run -d "$DEVICE_ID" ${DEFINE_ARGS[@]+"${DEFINE_ARGS[@]}"}
    ;;
  android)
    boot_android
    exec flutter run -d "$DEVICE_ID" ${DEFINE_ARGS[@]+"${DEFINE_ARGS[@]}"}
    ;;
  *)
    echo "Usage: $0 [ios|android]" >&2
    exit 1
    ;;
esac
