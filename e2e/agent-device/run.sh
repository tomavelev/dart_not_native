#!/usr/bin/env bash
# Runs the agent-device flows against the app on an Android device.
#
#   e2e/agent-device/run.sh [flow ...]
#
# Flows default to every flows/*.ad. Each flow says what it needs in comments
# at its top, as the Maestro flows of dart_not_native do:
#
#   # entry: android=lib/main.dart     the entry point to build and install
#   # state: clear                     start from a freshly installed app
#
# A flow with no `# entry:` line runs against the default one (below). The
# app is built once per entry point, however many flows share it.
#
# Options:
#   --device <serial>   adb serial (default: the only device attached)
#   --no-build          reuse whatever is already installed
#   --retries <n>       retry a failing flow up to n more times (default 0 -
#                       a flow that needs a retry is a flow to fix)
#
# Exits non-zero if any flow fails. What a run leaves behind is under
# e2e/agent-device/artifacts/ (git-ignored): agent-device's own per-attempt
# logs, a JUnit report per flow, and a screenshot of the screen each failing
# flow stopped on.
#
# Needs: adb, flutter, and agent-device (npm i -g agent-device) on the PATH.
set -euo pipefail

APP_ID="com.programtom.dart_not_native"
# Every example shares that application id, so every flow names the entry
# point it needs; this is only what a flow with no `# entry:` line gets.
DEFAULT_ENTRY="lib/main_native_gallery.dart"
BUILD_ARGS=""

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FLOWS="$HERE/flows"
ARTIFACTS="$HERE/artifacts"
AGENT_DEVICE="${AGENT_DEVICE:-agent-device}"

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

DEVICE=""
BUILD=1
RETRIES=0
SELECTED=()
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --retries) RETRIES="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) SELECTED+=("$1"); shift ;;
  esac
done

command -v "$AGENT_DEVICE" >/dev/null || {
  echo "agent-device is not installed: npm i -g agent-device" >&2; exit 1; }
[ -n "$DEVICE" ] || DEVICE="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
[ -n "$DEVICE" ] || { echo "No Android device; start an emulator first." >&2; exit 1; }
# A device asleep fails in ways that look like bugs in the app.
adb -s "$DEVICE" shell svc power stayon true >/dev/null 2>&1 || true

if [ ${#SELECTED[@]} -eq 0 ]; then
  SELECTED=("$FLOWS"/*.ad)
else
  # A name, a file name or a path: all of them mean a flow in flows/.
  resolved=()
  for name in "${SELECTED[@]}"; do
    case "$name" in
      /*) resolved+=("$name") ;;
      *.ad) resolved+=("$FLOWS/$(basename "$name")") ;;
      *) resolved+=("$FLOWS/$name.ad") ;;
    esac
  done
  SELECTED=("${resolved[@]}")
fi

# What a flow asks for in a `# <key>: ...` line.
directive() { grep -m1 "^# $2:" "$1" | sed "s/^# $2: *//" || true; }
entry_for() {
  local entry
  entry="$(directive "$1" entry | tr ' ' '\n' | sed -n 's/^android=//p')"
  echo "${entry:-$DEFAULT_ENTRY}"
}

INSTALLED=""
install_app() {
  local entry="$1"
  [ "$BUILD" = 1 ] || return 0
  [ "$entry" != "$INSTALLED" ] || return 0
  echo "== building $entry"
  # shellcheck disable=SC2086
  (cd "$ROOT" && flutter build apk --debug -t "$entry" $BUILD_ARGS >/dev/null)
  adb -s "$DEVICE" install -r "$ROOT/build/app/outputs/flutter-apk/app-debug.apk" >/dev/null
  INSTALLED="$entry"
}

# Flows that share an entry point run together, so each is built once.
IFS=$'\n' ORDERED=($(for flow in "${SELECTED[@]}"; do
  echo "$(entry_for "$flow")|$flow"
done | sort)); unset IFS

rm -rf "$ARTIFACTS"; mkdir -p "$ARTIFACTS"
failed=()
for item in "${ORDERED[@]}"; do
  flow="${item#*|}"
  name="$(basename "$flow" .ad)"
  [ -f "$flow" ] || { echo "no such flow: $flow" >&2; failed+=("$name"); continue; }
  install_app "${item%%|*}"
  if [ "$(directive "$flow" state)" = clear ]; then
    adb -s "$DEVICE" shell pm clear "$APP_ID" >/dev/null
  fi
  echo "== $name on $DEVICE"
  if ! "$AGENT_DEVICE" test "$flow" --platform android --serial "$DEVICE" \
      --retries "$RETRIES" --artifacts-dir "$ARTIFACTS/$name" \
      --report-junit "$ARTIFACTS/$name.xml"; then
    adb -s "$DEVICE" exec-out screencap -p > "$ARTIFACTS/$name-failure.png" || true
    echo "   screen at the failure: $ARTIFACTS/$name-failure.png"
    failed+=("$name")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "== failed: ${failed[*]}"
  exit 1
fi
echo "== all ${#ORDERED[@]} flows passed"
