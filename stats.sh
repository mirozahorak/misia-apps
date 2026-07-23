#!/usr/bin/env bash
# stats.sh — rough APK download counts from GitHub Releases.
#
# NOTE: these GitHub counters are UNRELIABLE for our setup — the moving
# `events-latest` asset is recreated on every publish, which resets its
# counter, and GitHub's counts are cached (not real-time).
#
# The authoritative, real-time download stats live on the server, counted via
# the /app/android redirect (table app_downloads). Get them with:
#
#     bin/rails app:downloads          # run on the misia71 server
#
set -euo pipefail
echo "GitHub release counters (rough — see note in this script):"
gh api repos/mirozahorak/misia-apps/releases --paginate --jq '
  [.[] | {tag: .tag_name, asset: .assets[].name, downloads: .assets[].download_count}]
  | (.[] | "\(.tag)\t\(.asset)\t\(.downloads)"),
    "----\tTOTAL\t\(map(.downloads) | add // 0)"
' | column -t -s $'\t'
echo
echo "Authoritative stats: run  bin/rails app:downloads  on the misia71 server."
