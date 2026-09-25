#!/usr/bin/env bash
# Builds the web version of every example into build/web_examples/<name>/.
#
# Web entries live in lib/examples/web/<name>.dart and render real DOM with
# Material CSS through package:dart_not_native/web.dart. They are compiled
# with plain dart2js (no Flutter engine, no canvas), then the web shell
# (index.html, dnn.css, style-kit CSS, vendored MDL/Materialize/fonts) is
# copied next to main.dart.js.
#
# Usage: maestro/web/build_examples.sh [name ...]   (default: all)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/web_examples"
SHELL_DIR="$ROOT/packages/native_bridge/web_shell"
cd "$ROOT"

if [ $# -gt 0 ]; then
  names=("$@")
else
  names=()
  for f in lib/examples/web/*.dart; do names+=("$(basename "$f" .dart)"); done
fi

mkdir -p "$OUT"
failed=()
for name in "${names[@]}"; do
  entry="lib/examples/web/$name.dart"
  dest="$OUT/$name"
  echo "==> Building $name ($entry)"
  rm -rf "$dest"
  mkdir -p "$dest"
  if dart compile js -O2 -o "$dest/main.dart.js" "$entry" >"$OUT/$name.log" 2>&1; then
    cp -r "$SHELL_DIR/." "$dest/"
    rm -f "$dest"/main.dart.js.deps
    echo "    ok ($(du -h "$dest/main.dart.js" | cut -f1) main.dart.js)"
  else
    echo "    FAILED (see $OUT/$name.log)"
    failed+=("$name")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed builds: ${failed[*]}"
  exit 1
fi
