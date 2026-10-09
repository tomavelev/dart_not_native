#!/usr/bin/env bash
# Everything that needs a real device, in one command.
#
#   tool/device_check.sh android            # a phone or a running emulator
#   tool/device_check.sh ios                # a booted simulator
#   tool/device_check.sh ios --device <udid>
#   tool/device_check.sh android --flows-only
#   tool/device_check.sh android --no-maestro      # a machine without Maestro
#
# This is deliberately not a CI lane. Booting a simulator or an emulator takes
# tens of minutes on a hosted runner, and those were the only lanes that ever
# hung - sixteen minutes with no output on a simulator that finishes in under
# two here. So it runs where the device already is: your machine.
#
# It does two things, in the order that fails fastest:
#
#   1. The Maestro flows, which drive the real views through the platform's
#      accessibility tree. This is the half that catches an app which compiles
#      and then refuses to launch - the iOS 26 UIScene failure was exactly
#      that, and no compile would ever have seen it.
#   2. On Android, the agent-device flows (e2e/agent-device), which go through
#      the same tree to the node types the Maestro flows were written before:
#      tappable boxes, layers, a dropdown, tabs, a bottom bar, a dialog. They
#      find views by id, so they also fail if a Key stops reaching the tree.
#   3. The integration tests, one file per invocation, which hand each
#      renderer one of every node type and every example app and listen for
#      what it could not draw.
#
# Run it after a change to the Kotlin or Swift renderers, and before a release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLATFORM="${1:-}"
shift || true
DEVICE=""
FLOWS_ONLY=0
TESTS_ONLY=0
MAESTRO_STAGE=1
AGENT_DEVICE_STAGE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --flows-only) FLOWS_ONLY=1; shift ;;
    --tests-only) TESTS_ONLY=1; shift ;;
    --no-maestro) MAESTRO_STAGE=0; shift ;;
    --no-agent-device) AGENT_DEVICE_STAGE=0; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$PLATFORM" in
  android|ios) ;;
  *) sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

# --- find the device, and say plainly when there is not one -----------------
if [ -z "$DEVICE" ]; then
  if [ "$PLATFORM" = android ]; then
    DEVICE="$(adb devices | awk '/\tdevice$/ {print $1; exit}')"
    [ -n "$DEVICE" ] || {
      echo "No Android device. Plug a phone in with USB debugging on, or start" >&2
      echo "an emulator, then check it appears in: adb devices" >&2
      exit 1
    }
    # A phone asleep in a drawer fails in ways that look like render bugs:
    # black screenshots, a first tap that only wakes the screen.
    adb -s "$DEVICE" shell svc power stayon true >/dev/null 2>&1 || true
    echo "== android: $DEVICE (kept awake; undo with: adb shell svc power stayon false)"
  else
    DEVICE="$(xcrun simctl list devices booted | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p' | head -1)"
    [ -n "$DEVICE" ] || {
      echo "No booted simulator. Start one, for example:" >&2
      echo "  xcrun simctl boot 'iPhone 18 Pro' && open -a Simulator" >&2
      exit 1
    }
    echo "== ios: $DEVICE"
  fi
fi

# --- the flows first: they fail fastest and catch the most ------------------
if [ "$TESTS_ONLY" = 0 ] && [ "$MAESTRO_STAGE" = 1 ]; then
  echo "== flows (maestro)"
  maestro/native/run.sh "$PLATFORM" --device "$DEVICE"
fi

# The agent-device lane is Android's for now: its flows were recorded there,
# and the iOS renderer's half of what they rely on has only drawn the examples.
if [ "$TESTS_ONLY" = 0 ] && [ "$AGENT_DEVICE_STAGE" = 1 ] && [ "$PLATFORM" = android ]; then
  echo "== flows (agent-device)"
  e2e/agent-device/run.sh --device "$DEVICE"
fi

# --- then the integration tests, one file at a time -------------------------
# One invocation per file on purpose: `flutter test integration_test` over the
# whole directory launches an app per file, and the second launch hangs on a
# simulator and fails outright on a desktop host.
if [ "$FLOWS_ONLY" = 0 ]; then
  for f in integration_test/*.dart; do
    echo "== $f"
    flutter test "$f" -d "$DEVICE"
  done
fi

echo "== done"
