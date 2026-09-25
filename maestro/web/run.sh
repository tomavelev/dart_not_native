#!/usr/bin/env bash
# Runs the Maestro web flows for the examples against their DOM builds.
#
#   maestro/web/run.sh generate [options] [example ...]
#       Records baseline screenshots into flows/screenshots/<kit>/<example>/
#       (existing baselines of the selected examples/kits are replaced).
#
#   maestro/web/run.sh verify [options] [example ...]
#       Runs the same flows and compares every checkpoint with its baseline.
#       Diff images of failed comparisons go to output/verify/<kit>/diffs/.
#
#   maestro/web/run.sh check [options] [example ...]
#       Behaviour only: runs the flows without taking or comparing screenshots.
#
# Options:
#   --kit <mdl|materialize|plain|all>  style kit(s) to run (default: all = mdl,materialize)
#   --no-build                         reuse build/web_examples
#   --port <n>                         static server port (default 8765)
#
# Examples default to every flows/*.yaml. Reports and debug artifacts are
# written to output/<mode>/<kit>/.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FLOWS="$HERE/flows"
SITE="$ROOT/build/web_examples"
MAESTRO="${MAESTRO:-$(command -v maestro || echo "$HOME/.maestro/bin/maestro")}"

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

[ $# -ge 1 ] || usage
MODE="$1"; shift
case "$MODE" in generate|verify|check) ;; *) usage ;; esac

KITS=(mdl materialize)
BUILD=1
PORT=8765
EXAMPLES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --kit)
      case "${2:-}" in
        all) KITS=(mdl materialize) ;;
        mdl|materialize|plain) KITS=("$2") ;;
        *) usage ;;
      esac
      shift 2 ;;
    --no-build) BUILD=0; shift ;;
    --port) PORT="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) EXAMPLES+=("$1"); shift ;;
  esac
done

if [ ${#EXAMPLES[@]} -eq 0 ]; then
  for f in "$FLOWS"/*.yaml; do EXAMPLES+=("$(basename "$f" .yaml)"); done
fi
FLOW_FILES=()
for e in "${EXAMPLES[@]}"; do
  [ -f "$FLOWS/$e.yaml" ] || { echo "No flow for '$e' ($FLOWS/$e.yaml)"; exit 2; }
  FLOW_FILES+=("$FLOWS/$e.yaml")
done

if [ "$BUILD" = 1 ]; then
  "$HERE/build_examples.sh" "${EXAMPLES[@]}"
fi

# Static server for the builds.
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SITE" >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
for _ in $(seq 50); do
  curl -sf "http://127.0.0.1:$PORT/" >/dev/null && break
  sleep 0.1
done
BASE_URL="http://127.0.0.1:$PORT"

status=0
for kit in "${KITS[@]}"; do
  out="$HERE/output/$MODE/$kit"
  rm -rf "$out"
  mkdir -p "$out"

  if [ "$MODE" = generate ]; then
    # takeScreenshot writes to <test-output-dir>/screenshots/<KIT>/<NAME>.png
    shots_root="$FLOWS"
    for e in "${EXAMPLES[@]}"; do rm -rf "$FLOWS/screenshots/$kit/$e"; done
  else
    shots_root="$out"
  fi

  echo "==> $MODE [$kit] ${EXAMPLES[*]}"
  if ! "$MAESTRO" test \
      --headless --screen-size 1280x800 \
      -e MODE="$MODE" -e KIT="$kit" -e BASE_URL="$BASE_URL" \
      --test-output-dir "$shots_root" \
      --debug-output "$out/debug" --flatten-debug-output \
      --format junit --output "$out/report.xml" \
      "${FLOW_FILES[@]}"; then
    status=1
  fi

  # Maestro writes comparison diffs inside the baseline tree (under a
  # doubled screenshots/<kit>/ path); move them to the output folder.
  if [ -d "$FLOWS/screenshots" ]; then
    diffs=$(find "$FLOWS/screenshots" -name '*_diff.png')
    if [ -n "$diffs" ]; then
      while IFS= read -r diff; do
        example="$(basename "$(dirname "$diff")")"
        mkdir -p "$out/diffs/$example"
        mv "$diff" "$out/diffs/$example/"
      done <<<"$diffs"
      echo "    screenshot diffs: $out/diffs"
    fi
    find "$FLOWS/screenshots" -mindepth 2 -type d -name screenshots -prune -exec rm -rf {} +
  fi
done

if [ "$MODE" = generate ] && [ $status = 0 ]; then
  echo "Baselines: $FLOWS/screenshots"
fi
exit $status
