#!/bin/zsh
set -euo pipefail
STROKA_TEST_APP="${1:?Usage: verify.zsh /path/to/diagnostic/Stroka.app [--interactive] [--live]}"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :StrokaDiagnostics' "$STROKA_TEST_APP/Contents/Info.plist" 2>/dev/null || true)" != "true" ]]; then
  echo "Build with STROKA_DIAGNOSTICS=1 before running diagnostic checks." >&2
  exit 2
fi
for STROKA_CHECK in quick-feed-check onboarding-check simple-setup-check saved-settings-check self-test feed-reliability-check short-content-check content-catalog-check; do
  "$STROKA_TEST_APP/Contents/MacOS/Stroka" "--$STROKA_CHECK"
done
python3 - <<'FIXTURE' | "$STROKA_TEST_APP/Contents/MacOS/Stroka" --feed-parser-check
import base64,datetime,json
stamp=datetime.datetime.now(datetime.timezone.utc).isoformat()
rss='<rss><channel><item><title>Fresh fixture</title><pubDate>'+stamp+'</pubDate></item></channel></rss>'
atom='<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Fresh Atom fixture</title><published>'+stamp+'</published></entry></feed>'
print(json.dumps([dict(name=name,url='https://fixture.invalid/feed',data=base64.b64encode(data.encode()).decode()) for name,data in [('RSS',rss),('Atom',atom)]]))
FIXTURE
if (( ${argv[(Ie)--interactive]} )); then
  for STROKA_CHECK in expanded-catalog-check offline-label-check multi-row-check desktop-edge-check editorial-check broadcast-edge-check compact-check dual-check separator-check row-speed-check motion-behavior-check preview-integration-check strip-double-click-check simple-setup-ui-check; do
    "$STROKA_TEST_APP/Contents/MacOS/Stroka" "--$STROKA_CHECK"
  done
fi
if (( ${argv[(Ie)--live]} )); then
  for STROKA_CHECK in telegram-live-add-check open-market-check tv-bridge-check phone-remote-check translation-live-check; do
    "$STROKA_TEST_APP/Contents/MacOS/Stroka" "--$STROKA_CHECK"
  done
fi
