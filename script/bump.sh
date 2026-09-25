#!/bin/bash
# Moves VERSION forward and makes sure the release notes come with it.
#
#   script/bump.sh 0.9.0 [--dry-run]
#   script/bump.sh --help
#
# Refuses anything that is not a higher X.Y.Z than VERSION (a downgrade would
# hand Sparkle a build number it has already passed and existing installs
# would never update). When NOTES.md has no `## <new-version>` section yet, a
# stub is inserted at the top for the human to fill in — build.sh reads that
# section into the Sparkle update window, and script/release.sh --publish
# refuses to ship without it.
set -euo pipefail

cd "$(dirname "$0")/.."
. script/lib-version.sh
ROOT="$(version_root)"

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'
}

DRY_RUN=0
NEW=""
for ARG in "$@"; do
  case "$ARG" in
    --help|-h) usage; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    -*) echo "unknown flag: $ARG (see --help)" >&2; exit 1 ;;
    *) [ -z "$NEW" ] || { echo "one version at a time" >&2; exit 1; }; NEW="$ARG" ;;
  esac
done
[ -n "$NEW" ] || { echo "usage: script/bump.sh <new-version> [--dry-run]" >&2; exit 1; }

CURRENT="$(version_read)"
version_valid "$CURRENT" || { echo "VERSION is not semver: '$CURRENT'" >&2; exit 1; }
version_valid "$NEW" || { echo "not semver X.Y.Z: '$NEW'" >&2; exit 1; }
CMP="$(version_cmp "$NEW" "$CURRENT")"
[ "$CMP" = "1" ] || { echo "refusing: $NEW is not newer than $CURRENT" >&2; exit 1; }
[ "$(version_patch "$NEW")" -lt 100 ] || { echo "PATCH must stay below 100 for the Sparkle build number" >&2; exit 1; }

if [ "$DRY_RUN" = "1" ]; then
  echo "would write VERSION: $CURRENT → $NEW"
  if notes_has_section "$ROOT" "$NEW"; then
    echo "NOTES.md already has ## $NEW"
  else
    echo "would insert NOTES.md stub: ## $NEW"
  fi
  exit 0
fi

printf '%s\n' "$NEW" > "$ROOT/VERSION"
echo "VERSION: $CURRENT → $NEW"

if notes_has_section "$ROOT" "$NEW"; then
  echo "NOTES.md already has ## $NEW"
else
  # Newest first: ahead of the first existing section, else appended.
  python3 - "$ROOT/NOTES.md" "$NEW" <<'EOF'
import sys
path, ver = sys.argv[1], sys.argv[2]
stub = "## %s\n\n- " % ver
with open(path) as f:
    lines = f.readlines()
for i, line in enumerate(lines):
    if line.startswith("## "):
        lines.insert(i, stub + "\n\n")
        break
else:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.append("\n" + stub + "\n")
with open(path, "w") as f:
    f.writelines(lines)
EOF
  echo "inserted NOTES.md stub: ## $NEW — fill it in before releasing"
fi

echo "next: fill in NOTES.md, then ./build.sh release ship && script/release.sh --publish"
