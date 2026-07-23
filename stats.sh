#!/usr/bin/env bash
# stats.sh — APK download counts for all releases in this repo.
#
# Note: the moving `<app>-latest` tag is recreated on every publish, so its
# counter only covers the current version; the versioned releases (events-v…)
# keep their counts forever.
set -euo pipefail
gh api repos/mirozahorak/misia-apps/releases --paginate --jq '
  [.[] | {tag: .tag_name, asset: .assets[].name, downloads: .assets[].download_count}]
  | (.[] | "\(.tag)\t\(.asset)\t\(.downloads)"),
    "----\tTOTAL\t\(map(.downloads) | add // 0)"
' | column -t -s $'\t'
