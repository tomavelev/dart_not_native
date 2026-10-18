#!/usr/bin/env bash
# Times the two device-testing tools against each other on the examples.
#
#   tool/e2e_benchmark.sh [android|ios] [--runs N] [--device <id>]
#                         [--ios-agent-device]
#
# Two comparisons, each run N times (default 3) with the app built and
# installed once beforehand, so a time is the tool driving the app and not
# a build:
#
#   A. The same Maestro YAML, run by Maestro and by agent-device's Maestro
#      engine (`agent-device test --maestro`) - Android only, which is where
#      that engine runs these flows.
#   B. The same scenario written for each: the controls gallery's three tabs
#      as agent-device `.ad` flows (e2e/agent-device/flows) and as Maestro
#      flows (maestro/native/flows/gallery_*.yaml).
#
# On iOS, B times Maestro alone unless --ios-agent-device is given: the
# `.ad` flows are written against Android's tree and stop on iOS at steps
# that read it differently (an app bar action, a slider, a field), and
# agent-device leaves its XCUITest runner going afterwards, which a Maestro
# run on the same simulator then reads nothing through - so the runner is
# stopped after each of its runs here.
#
# Prints a table: each flow, each tool, how many runs passed, and the median
# and fastest wall time of the runs that passed. What each run printed is
# kept under build/e2e_benchmark/.
#
# Needs: flutter, maestro, agent-device and adb (or Xcode) on the PATH.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PLATFORM="${1:-android}"
shift || true
RUNS=3
DEVICE=""
IOS_AGENT_DEVICE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --ios-agent-device) IOS_AGENT_DEVICE=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

MAESTRO="${MAESTRO:-$(command -v maestro || echo "$HOME/.maestro/bin/maestro")}"
AGENT_DEVICE="${AGENT_DEVICE:-agent-device}"
OUT="$ROOT/build/e2e_benchmark"
mkdir -p "$OUT"

if [ "$PLATFORM" = android ]; then
  APP_ID="com.programtom.dart_not_native"
  [ -n "$DEVICE" ] || DEVICE="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
else
  APP_ID="com.programtom.dartNotNative"
  [ -n "$DEVICE" ] || DEVICE="$(xcrun simctl list devices booted -j |
    python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];print(next((x["udid"] for v in d.values() for x in v), ""))')"
fi
[ -n "$DEVICE" ] || { echo "no $PLATFORM device" >&2; exit 1; }

now() { python3 -c 'import time; print(time.time())'; }

installed=""
install() {
  local entry="$1"
  [ "$installed" = "$entry" ] && return 0
  echo "== building $entry" >&2
  if [ "$PLATFORM" = android ]; then
    flutter build apk --debug -t "$entry" >/dev/null &&
      adb -s "$DEVICE" install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null
  else
    flutter build ios --simulator --debug --no-codesign -t "$entry" >/dev/null &&
      xcrun simctl install "$DEVICE" build/ios/iphonesimulator/Runner.app
  fi
  installed="$entry"
}

# One run of one tool on one flow: prints "pass <seconds>" or "fail <seconds>".
run_once() {
  local tool="$1" flow="$2" log="$3" start end status
  start="$(now)"
  case "$tool" in
    maestro)
      "$MAESTRO" --device "$DEVICE" test -e APP_ID="$APP_ID" "$flow" >"$log" 2>&1 ;;
    agent-device-maestro)
      "$AGENT_DEVICE" test "$flow" --maestro --platform "$PLATFORM" \
        --serial "$DEVICE" -e APP_ID="$APP_ID" \
        --artifacts-dir "$OUT/artifacts" >"$log" 2>&1 ;;
    agent-device)
      # A `.ad` flow starts from a cleared app, as e2e/agent-device/run.sh
      # gives it; Maestro's flows clear it themselves.
      [ "$PLATFORM" = android ] && adb -s "$DEVICE" shell pm clear "$APP_ID" >/dev/null
      local script="$flow"
      if [ "$PLATFORM" = ios ]; then
        script="$OUT/$(basename "$flow")"
        sed -e 's/platform=android/platform=ios/' \
          -e "s/com.programtom.dart_not_native/$APP_ID/" "$flow" >"$script"
      fi
      "$AGENT_DEVICE" test "$script" --platform "$PLATFORM" \
        $([ "$PLATFORM" = android ] && echo --serial "$DEVICE" || echo --udid "$DEVICE") \
        --artifacts-dir "$OUT/artifacts" >"$log" 2>&1 ;;
  esac
  status=$?
  # Its iOS runner stays up after the flow, and blinds the next tool.
  if [ "$tool" = agent-device ] && [ "$PLATFORM" = ios ]; then
    pkill -f AgentDeviceRunnerUITests >/dev/null 2>&1 || true
  fi
  end="$(now)"
  python3 -c "print('pass' if $status == 0 else 'fail', round($end - $start, 1))"
}

# Runs [tool] on [flow] RUNS times and prints a table row.
measure() {
  local label="$1" tool="$2" flow="$3" times=() passed=0 i result
  for ((i = 1; i <= RUNS; i++)); do
    result="$(run_once "$tool" "$flow" "$OUT/$label-$tool-$i.log")"
    echo "   $label / $tool / run $i: $result" >&2
    if [ "${result%% *}" = pass ]; then
      passed=$((passed + 1))
      times+=("${result#* }")
    fi
  done
  python3 - "$label" "$tool" "$passed" "$RUNS" "${times[@]:-}" <<'EOF'
import statistics, sys
label, tool, passed, runs, *times = sys.argv[1:]
times = [float(t) for t in times if t]
median = f"{statistics.median(times):.1f} s" if times else "-"
fastest = f"{min(times):.1f} s" if times else "-"
print(f"| {label} | {tool} | {passed}/{runs} | {median} | {fastest} |")
EOF
}

entry_of() { grep -m1 '^# entry:' "$1" | tr ' ' '\n' | sed -n "s/^$PLATFORM=//p"; }

rows=()
echo "| Flow | Tool | Passed | Median | Fastest |"
echo "|---|---|---|---|---|"

# A: one YAML, two engines.
if [ "$PLATFORM" = android ]; then
  for name in counter inbox textinput_android focus a11y_android \
      gallery_touch gallery_choose gallery_feedback; do
    flow="maestro/native/flows/$name.yaml"
    entry="$(entry_of "$flow")"
    [ -n "$entry" ] || continue
    install "$entry" || { echo "| $name | (build failed) | | | |"; continue; }
    measure "$name.yaml" maestro "$flow"
    measure "$name.yaml" agent-device-maestro "$flow"
  done
fi

# B: one scenario, each tool's own flow.
for tab in touch choose feedback; do
  ad="e2e/agent-device/flows/gallery_$tab.ad"
  yaml="maestro/native/flows/gallery_$tab.yaml"
  install "lib/main_native_gallery.dart" || continue
  if [ "$PLATFORM" = android ] || [ "$IOS_AGENT_DEVICE" = 1 ]; then
    measure "gallery_$tab (own)" agent-device "$ad"
  fi
  measure "gallery_$tab (own)" maestro "$yaml"
done
