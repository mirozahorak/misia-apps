#!/usr/bin/env bash
# stats.sh — APK download stats from both sources:
#   1. Server (authoritative): counted via the /app/android redirect, exposed
#      as JSON at https://nasa.misia.sk/app/stats — real-time, never resets.
#   2. GitHub release counters (rough): the moving `events-latest` asset is
#      recreated on every publish, which resets its counter, and GitHub's
#      counts are cached — so treat these as a loose secondary signal only.
set -euo pipefail

STATS_URL="${MISIA_APP_STATS_URL:-https://nasa.misia.sk/app/stats}"

echo "== Server downloads (authoritative) =="
if json=$(curl -fsS --max-time 15 "$STATS_URL" 2>/dev/null); then
  echo "$json" | jq -r '
    .android
    | "  total:        \(.total)",
      "  last 7 days:  \(.last_7_days)",
      "  last 30 days: \(.last_30_days)",
      "",
      "  per day (last 14):",
      (.per_day | to_entries[] | "    \(.key)  \(.value)")
  '
else
  echo "  (could not reach $STATS_URL)"
fi

echo
echo "== GitHub release counters (rough — reset on each publish) =="
gh api repos/mirozahorak/misia-apps/releases --paginate --jq '
  [.[] | {tag: .tag_name, asset: .assets[].name, downloads: .assets[].download_count}]
  | (.[] | "  \(.tag)\t\(.asset)\t\(.downloads)"),
    "  ----\tTOTAL\t\(map(.downloads) | add // 0)"
' | column -t -s $'\t'
