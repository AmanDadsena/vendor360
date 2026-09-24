#!/usr/bin/env bash
#
# Everything that has to be green before a commit: the backend suite, and
# analyze + test for each of the three Dart packages.
#
# It exists because a chain like `flutter test | grep passed && git commit`
# gates on grep's exit code, not the test's, which is how a red suite gets
# committed twice in a row. One script, one exit code, no chance to read the
# wrong one.
#
#   ./check.sh          everything
#   ./check.sh dart     skip the Python suite
#
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ONLY=${1:-all}

# Windows installs are not usually on PATH under Git Bash; fall back to the
# common location rather than failing with "command not found".
FLUTTER=$(command -v flutter || echo "D:/flutter/bin/flutter.bat")
DART=$(command -v dart || echo "D:/flutter/bin/dart.bat")
PYTHON=$(command -v python || command -v python3)

status=0

run() {
  local name=$1; shift
  local log code last
  log=$("$@" 2>&1)
  code=$?
  last=$(printf '%s\n' "$log" \
    | grep -E "All tests passed|Some tests failed|No issues found|issues? found|passed|failed" \
    | tail -1)
  printf '%-22s exit=%s  %s\n' "$name" "$code" "$last"
  if [ "$code" -ne 0 ]; then
    status=1
    # Enough of the failure to act on, without pasting the whole run.
    printf '%s\n' "$log" \
      | grep -E "\[E\]|error -|warning -|FAILED|Expected|Actual" | head -12
  fi
}

if [ "$ONLY" != "dart" ]; then
  cd "$ROOT/backend" && run "backend test" "$PYTHON" -m pytest -q
fi

cd "$ROOT/packages/vendor360_core" \
  && run "core analyze" "$DART" analyze \
  && run "core test" "$DART" test

cd "$ROOT/packages/vendor360_ui" \
  && run "ui analyze" "$FLUTTER" analyze \
  && run "ui test" "$FLUTTER" test

cd "$ROOT/app" \
  && run "app analyze" "$FLUTTER" analyze \
  && run "app test" "$FLUTTER" test

[ "$status" -eq 0 ] && echo "all green" || echo "SOMETHING IS RED"
exit $status
