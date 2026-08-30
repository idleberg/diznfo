#!/usr/bin/env bash
# Install the built app so QuickLook picks up the preview extension.
#
# macOS only registers app extensions from apps in a standard location, and it
# caches LaunchServices data aggressively — including registrations for app
# bundles that were renamed or deleted. That is the usual reason a freshly
# built preview extension appears to do nothing at all.
set -euo pipefail

cd "$(dirname "$0")/.."
built="$PWD/build/Quicklook NFO.app"
installed="/Applications/Quicklook NFO.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [[ "${1:-}" == "--remove" ]]; then
  "$lsregister" -u "$installed" 2>/dev/null || true
  rm -rf "$installed"
  qlmanage -r >/dev/null 2>&1 || true
  echo "Removed $installed"
  exit 0
fi

[[ -d "$built" ]] || {
  echo "No build at $built — run 'mise run build' first." >&2
  exit 1
}

rm -rf "$installed"
cp -R "$built" "$installed"
"$lsregister" -f -R "$installed"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

# Launching the app is what makes macOS register its embedded extension.
open -g "$installed"

echo "Installed $installed"
echo "Verify with: pluginkit -mAv | grep com.idleberg"
