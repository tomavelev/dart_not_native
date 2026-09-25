#!/usr/bin/env bash
# Runs the Maestro flows against the *native* renderers on a device.
#
#   maestro/native/run.sh android [flow ...]
#   maestro/native/run.sh ios     [flow ...]
#
# Flows default to the ones that apply to the platform (flows/*.yaml, minus
# the ones named for the other one). Each flow says which entry point it needs
# in an `# entry:` comment; this builds and installs that app before running
# it, because every example shares one application id.
#
# Options:
#   --device <id>   adb serial or simulator udid (default: the only one booted)
#   --no-build      reuse whatever is already installed
#
# Why this exists: `integration_test/native_renderer_test.dart` asks both
# renderers to draw every node type and listens for errors, which says nothing
# about whether a tap or a keystroke reaches the app. These flows drive the
# real views through the platform's own accessibility tree - the same one a
# screen reader uses - and assert what the app did about it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FLOWS="$HERE/flows"
MAESTRO="${MAESTRO:-$(command -v maestro || echo "$HOME/.maestro/bin/maestro")}"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

[ $# -ge 1 ] || usage
PLATFORM="$1"; shift
case "$PLATFORM" in android|ios) ;; *) usage ;; esac

DEVICE=""
BUILD=1
SELECTED=()
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    -h|--help) usage ;;
    *) SELECTED+=("$1"); shift ;;
  esac
done

if [ "$PLATFORM" = android ]; then
  APP_ID="com.programtom.dart_not_native"
  [ -n "$DEVICE" ] || DEVICE="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
  [ -n "$DEVICE" ] || { echo "No Android device; start an emulator first." >&2; exit 1; }
else
  APP_ID="com.programtom.dartNotNative"
  [ -n "$DEVICE" ] || DEVICE="$(xcrun simctl list devices booted -j |
    python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];print(next((x["udid"] for v in d.values() for x in v), ""))')"
  [ -n "$DEVICE" ] || { echo "No booted simulator; boot one first." >&2; exit 1; }
fi

# Flows for this platform: the shared ones plus the ones named for it.
if [ ${#SELECTED[@]} -eq 0 ]; then
  for f in "$FLOWS"/*.yaml; do
    name="$(basename "$f" .yaml)"
    case "$name" in
      *_android) [ "$PLATFORM" = android ] && SELECTED+=("$f") ;;
      *_ios) [ "$PLATFORM" = ios ] && SELECTED+=("$f") ;;
      *) SELECTED+=("$f") ;;
    esac
  done
else
  # A name, a file name or a path: all of them mean a flow in flows/.
  resolved=()
  for name in "${SELECTED[@]}"; do
    case "$name" in
      /*) resolved+=("$name") ;;
      *.yaml) resolved+=("$FLOWS/$(basename "$name")") ;;
      *) resolved+=("$FLOWS/$name.yaml") ;;
    esac
  done
  SELECTED=("${resolved[@]}")
fi

# The entry point a flow needs, from its `# entry:` line.
entry_for() {
  local line
  line="$(grep -m1 '^# entry:' "$1" || true)"
  echo "$line" | tr ' ' '\n' | sed -n "s/^$PLATFORM=//p"
}

install_app() {
  local entry="$1"
  [ "$BUILD" = 1 ] || return 0
  echo "== building $entry for $PLATFORM"
  if [ "$PLATFORM" = android ]; then
    (cd "$ROOT" && flutter build apk --debug -t "$entry" >/dev/null)
    adb -s "$DEVICE" install -r "$ROOT/build/app/outputs/flutter-apk/app-debug.apk" >/dev/null
  else
    (cd "$ROOT" && flutter build ios --simulator --debug --no-codesign -t "$entry" >/dev/null)
    xcrun simctl install "$DEVICE" "$ROOT/build/ios/iphonesimulator/Runner.app"
  fi
}

failed=0
for flow in "${SELECTED[@]}"; do
  entry="$(entry_for "$flow")"
  if [ -z "$entry" ]; then
    echo "== skipping $(basename "$flow"): no entry point for $PLATFORM"
    continue
  fi
  install_app "$entry"
  echo "== $(basename "$flow") on $DEVICE"
  "$MAESTRO" --device "$DEVICE" test -e APP_ID="$APP_ID" "$flow" || failed=1
done
exit "$failed"
