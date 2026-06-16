#!/usr/bin/env bash
# Run Flutter integration tests across platforms.
# Usage:
#   ./scripts/integration_tests.sh [--platforms chrome,macos,android,ios] [--test <file>] [extra flutter args...]
#
# Examples:
#   ./scripts/integration_tests.sh
#   ./scripts/integration_tests.sh --platforms chrome,macos
#   ./scripts/integration_tests.sh --platforms android --test integration_test/core_dice_test.dart
#   ./scripts/integration_tests.sh --platforms android \
#       --dart-define DDDICE_TOKEN=xxx --dart-define DDDICE_ROOM=yyy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure Android SDK tools are on PATH (for adb, emulator).
ANDROID_SDK="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
export PATH="${ANDROID_SDK}/platform-tools:${ANDROID_SDK}/emulator:${PATH}"

# --------------------------------------------------------------------------- #
# Defaults
# --------------------------------------------------------------------------- #
PLATFORMS="chrome,macos"
TEST_TARGET=""        # empty → run all integration_test/**_test.dart
EXTRA_ARGS=()

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --platforms)
      PLATFORMS="$2"
      shift 2
      ;;
    --test)
      TEST_TARGET="$2"
      shift 2
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

IFS=',' read -ra PLATFORM_LIST <<< "$PLATFORMS"

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
log() { echo "[integration_tests] $*" >&2; }

# Runs "$@" with a hard wall-clock timeout (in seconds). Returns the command's
# exit code, or 124 if it had to be killed for running too long.
# (No `timeout`/`gtimeout` binary is assumed to be installed.)
run_with_timeout() {
  local timeout_secs="$1"
  shift
  "$@" &
  local cmd_pid=$!
  (
    sleep "$timeout_secs"
    kill -TERM "$cmd_pid" 2>/dev/null
    sleep 5
    kill -KILL "$cmd_pid" 2>/dev/null
  ) &
  local watcher_pid=$!
  local exit_code=0
  wait "$cmd_pid" || exit_code=$?
  kill "$watcher_pid" 2>/dev/null
  wait "$watcher_pid" 2>/dev/null
  return "$exit_code"
}

# Returns the first booted Android emulator (e.g. "emulator-5554"), or ""
find_android_emulator() {
  adb devices 2>/dev/null \
    | awk '/^emulator-[0-9]+[[:space:]]+device$/{print $1; exit}'
}

# Returns the name of the first available iOS simulator that's booted, or ""
find_ios_simulator() {
  xcrun simctl list devices --json 2>/dev/null \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get('devices', {}).items():
    for d in devices:
        if d.get('state') == 'Booted':
            print(d['udid'])
            sys.exit(0)
"
}

# Boot an Android emulator if none is running; returns the device id
ensure_android_emulator() {
  local dev
  dev="$(find_android_emulator)"
  if [[ -n "$dev" ]]; then
    log "Using existing Android emulator: $dev"
    echo "$dev"
    return
  fi

  # Pick the first available AVD
  local avd
  avd="$(emulator -list-avds 2>/dev/null | head -n1)"
  if [[ -z "$avd" ]]; then
    log "ERROR: No Android AVDs found. Create one with Android Studio or avdmanager."
    exit 1
  fi

  log "Starting Android emulator: $avd"
  emulator -avd "$avd" -no-snapshot-load -no-audio -no-window &
  EMULATOR_PID=$!

  log "Waiting for emulator to boot (up to 120s)..."
  adb wait-for-device
  for i in $(seq 1 60); do
    local boot_anim
    boot_anim="$(adb shell getprop init.svc.bootanim 2>/dev/null || true)"
    [[ "$boot_anim" == "stopped" ]] && break
    sleep 2
  done

  dev="$(find_android_emulator)"
  log "Emulator ready: $dev"
  echo "$dev"
}

# Boot an iOS simulator if none is running; returns the udid
ensure_ios_simulator() {
  local udid
  udid="$(find_ios_simulator)"
  if [[ -n "$udid" ]]; then
    log "Using existing iOS simulator: $udid"
    echo "$udid"
    return
  fi

  # Pick the most recent iPhone simulator available
  local dev_name
  dev_name="$(xcrun simctl list devices available --json \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
# Prefer iPhone 16, fall back to any iPhone
for runtime in sorted(data.get('devices', {}).keys(), reverse=True):
    for d in data['devices'][runtime]:
        if 'iPhone' in d.get('name', '') and d.get('isAvailable', False):
            print(d['udid'])
            sys.exit(0)
" 2>/dev/null)"

  if [[ -z "$dev_name" ]]; then
    log "ERROR: No iOS simulators available. Install Xcode simulators."
    exit 1
  fi

  log "Booting iOS simulator: $dev_name"
  xcrun simctl boot "$dev_name"
  # Wait until booted
  for i in $(seq 1 30); do
    local state
    state="$(xcrun simctl list devices --json \
      | python3 -c "
import json, sys
data = json.load(sys.stdin)
for rt, devs in data.get('devices', {}).items():
    for d in devs:
        if d.get('udid') == '$dev_name':
            print(d.get('state',''))
            sys.exit(0)
" 2>/dev/null)"
    [[ "$state" == "Booted" ]] && break
    sleep 2
  done

  echo "$dev_name"
}

# --------------------------------------------------------------------------- #
# Run tests on a single device
# --------------------------------------------------------------------------- #
run_tests() {
  local label="$1"
  local device_flag="$2"    # e.g. "-d chrome" or "-d emulator-5554"
  local target_override="${3:-}" # optional: overrides TEST_TARGET and default

  log "━━━ Running integration tests on $label ━━━"

  local args=("test" "--no-pub" "--dart-define=INTEGRATION_TEST=true")
  [[ -n "$device_flag" ]] && args+=($device_flag)

  if [[ -n "$target_override" ]]; then
    args+=("$target_override")
  elif [[ -n "$TEST_TARGET" ]]; then
    args+=("$TEST_TARGET")
  else
    args+=("integration_test/")
  fi

  args+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")

  cd "$PROJECT_DIR"
  flutter "${args[@]}" && log "PASS: $label" || { log "FAIL: $label"; return 1; }
}

# Runs the dddice real (non-guest) auth flow test against a local
# DddiceMockServer (see lib/testing/dddice_mock_server.dart). This needs its
# own DDDICE_BASE_URL dart-define pointing at the mock, so it can't be
# bundled into all_tests.dart's single binary alongside the real-dddice.com
# tests in dddice_test.dart (those need the real base URL). Not run on
# Chrome/web -- the mock binds a dart:io socket, which web builds can't do.
run_dddice_mock_test() {
  local label="$1"
  local device_flag="$2"

  log "━━━ Running dddice real-auth mock test on $label ━━━"
  cd "$PROJECT_DIR"
  flutter test --no-pub --dart-define=INTEGRATION_TEST=true \
      --dart-define=DDDICE_BASE_URL=http://127.0.0.1:18765/api/1.0 \
      $device_flag \
      integration_test/dddice_real_auth_test.dart \
    && log "PASS: $label (dddice mock)" || { log "FAIL: $label (dddice mock)"; return 1; }
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
log "Platforms: ${PLATFORM_LIST[*]}"

PASS=()
FAIL=()

for platform in "${PLATFORM_LIST[@]}"; do
  case "$platform" in
    chrome|web)
      # flutter drive on web requires chromedriver on port 4444.
      # The DWDS debug-service connection is a known timing race (flutter#181357).
      # Crucially, `flutter drive` does not reliably fail fast when this race is
      # lost -- it can hang indefinitely instead of exiting -- so each attempt is
      # wrapped in a hard wall-clock timeout rather than just relying on its exit
      # code, and we retry once with a fresh chromedriver if an attempt times out
      # or fails outright.
      log "━━━ Running integration tests on Chrome ━━━"
      cd "$PROJECT_DIR"
      chrome_target="${TEST_TARGET:-integration_test/all_tests.dart}"
      chrome_passed=false
      CHROMEDRIVER_PID=""
      for chrome_attempt in 1 2; do
        [[ -n "$CHROMEDRIVER_PID" ]] && kill "$CHROMEDRIVER_PID" 2>/dev/null || true
        CHROMEDRIVER_PID=""
        pkill -f "test-type=webdriver" 2>/dev/null || true
        if ! curl -s http://localhost:4444/status >/dev/null 2>&1; then
          log "Starting chromedriver (attempt ${chrome_attempt})..."
          npx chromedriver --port=4444 >/dev/null 2>&1 &
          CHROMEDRIVER_PID=$!
          sleep 3
        fi
        # --web-browser-flag args suppress Chrome features that cause DWDS races.
        if run_with_timeout 480 flutter drive --no-pub --dart-define=INTEGRATION_TEST=true \
            --driver=test_driver/integration_test.dart \
            --target="$chrome_target" -d chrome \
            --web-browser-flag=--disable-extensions \
            --web-browser-flag=--disable-component-update \
            --web-browser-flag=--no-first-run \
            "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"; then
          chrome_passed=true
          break
        fi
        [[ $chrome_attempt -lt 2 ]] && log "Chrome attempt ${chrome_attempt} failed or timed out, retrying..." && sleep 5
      done
      [[ -n "$CHROMEDRIVER_PID" ]] && kill "$CHROMEDRIVER_PID" 2>/dev/null || true
      pkill -f "test-type=webdriver" 2>/dev/null || true
      $chrome_passed && { log "PASS: chrome"; PASS+=(chrome); } || { log "FAIL: chrome"; FAIL+=(chrome); }
      ;;
    macos)
      # macOS can only run one app instance at a time, so use the combined entry
      # point that loads all test files in a single process.
      run_tests "macOS" "-d macos" "integration_test/all_tests.dart" \
        && PASS+=(macos) || FAIL+=(macos)
      run_dddice_mock_test "macOS" "-d macos" \
        && PASS+=(macos-dddice-mock) || FAIL+=(macos-dddice-mock)
      ;;
    android)
      ANDROID_DEV="$(ensure_android_emulator)"
      run_tests "Android ($ANDROID_DEV)" "-d $ANDROID_DEV" "integration_test/all_tests.dart" \
        && PASS+=(android) || FAIL+=(android)
      run_dddice_mock_test "Android ($ANDROID_DEV)" "-d $ANDROID_DEV" \
        && PASS+=(android-dddice-mock) || FAIL+=(android-dddice-mock)
      ;;
    ios)
      IOS_SIM="$(ensure_ios_simulator)"
      run_tests "iOS ($IOS_SIM)" "-d $IOS_SIM" "integration_test/all_tests.dart" \
        && PASS+=(ios) || FAIL+=(ios)
      run_dddice_mock_test "iOS ($IOS_SIM)" "-d $IOS_SIM" \
        && PASS+=(ios-dddice-mock) || FAIL+=(ios-dddice-mock)
      ;;
    *)
      log "Unknown platform '$platform'. Valid: chrome, macos, android, ios"
      FAIL+=("$platform")
      ;;
  esac
done

# --------------------------------------------------------------------------- #
# Summary
# --------------------------------------------------------------------------- #
echo ""
log "━━━ Results ━━━"
[[ ${#PASS[@]} -gt 0 ]] && log "PASS: ${PASS[*]}"
[[ ${#FAIL[@]} -gt 0 ]] && log "FAIL: ${FAIL[*]}"

[[ ${#FAIL[@]} -eq 0 ]]
