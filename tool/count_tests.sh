#!/usr/bin/env bash
# Counts the three test suites and, with --write, puts the numbers into TODO.md.
#
#   tool/count_tests.sh            # print them
#   tool/count_tests.sh --write    # print them and update TODO.md
#
# The counts exist because TODO.md's "What is already solid" quotes them, and a
# number typed by hand goes stale the next time anyone adds a test - it did,
# twice, on 2026-09-24 alone. So it is measured here instead of remembered.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The last "+N" a run prints is the number of tests that passed.
count() { grep -oE '\+[0-9]+' | tail -1 | tr -d '+'; }

echo "counting - this runs all three suites, so it takes a minute" >&2

app=$(flutter test 2>&1 | count)
pkg=$(cd packages/native_bridge && flutter test 2>&1 | count)
web=$(cd packages/native_bridge && flutter test --platform chrome test/web_ui 2>&1 | count)

for n in "$app" "$pkg" "$web"; do
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "a suite did not report a count - is it red?" >&2; exit 1; }
done

total=$((app + pkg + web))
today=$(date +%Y-%m-%d)
line="  (${pkg} in the package, ${app} for the example apps and goldens, ${web} in the browser,"

echo "package: $pkg"
echo "example apps and goldens: $app"
echo "browser: $web"
echo "total: $total"

if [ "${1:-}" = "--write" ]; then
  python3 - "$total" "$line" "$today" <<'PY'
import re, sys
total, line, today = sys.argv[1], sys.argv[2], sys.argv[3]
p = 'TODO.md'
s = open(p, encoding='utf-8').read()
pattern = (
    r'covered by [0-9,]+ tests\n'
    r'  \([0-9]+ in the package, [0-9]+ for the example apps and goldens, '
    r'[0-9]+ in the browser,\n  counted [0-9-]+\)'
)
# Whether the sentence is there and whether it needs changing are two
# questions. Asking them as one reports a reworded file every time the counts
# happen to be right already, which is the ordinary case.
if not re.search(pattern, s):
    sys.exit('could not find the counts sentence in TODO.md - has it been reworded?')
new = re.sub(pattern, f'covered by {total} tests\n{line}\n  counted {today})', s, count=1)
if new == s:
    print(f'TODO.md already says {total} tests, counted {today} - nothing to do')
else:
    open(p, 'w', encoding='utf-8').write(new)
    print(f'TODO.md updated: {total} tests, counted {today}')
PY
fi
