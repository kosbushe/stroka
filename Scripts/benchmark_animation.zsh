#!/bin/zsh
# Current desktop modes only; no live network and no concurrent compilation.
set -euo pipefail
STROKA_TEST_APP="${1:?Usage: benchmark_animation.zsh /path/Stroka.app}"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :StrokaDiagnostics' "$STROKA_TEST_APP/Contents/Info.plist" 2>/dev/null || true)" != "true" ]]; then
  echo "Build with STROKA_DIAGNOSTICS=1 before running diagnostic checks." >&2
  exit 2
fi
for STROKA_CASE in four-information-rows three-information-markets desktop-strip glass-desktop-strip minimal-desktop-strip night-desktop-strip paused hidden; do
  "$STROKA_TEST_APP/Contents/MacOS/Stroka" --animation-check --animation-case "$STROKA_CASE"
done
