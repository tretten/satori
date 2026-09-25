#!/bin/bash
# Shared version helpers for script/bump.sh and script/release.sh.
#
# VERSION (repo root) is the single source for the marketing version. The
# Sparkle build number is derived from it — MINOR*100+PATCH, e.g. 0.8.0 →
# 800 — so the two never drift apart. Monotonic while the major stays 0 and
# PATCH < 100; anything else fails loudly instead of shipping a build number
# Sparkle would silently ignore. Same rule as build.sh; kept in one place so
# the release scripts cannot disagree with the build.
#
# Sourced, never executed:  . "$(dirname "$0")/lib-version.sh"

# Repo root regardless of where the caller was invoked from.
version_root() {
  (cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)
}

version_read() {
  tr -d '[:space:]' < "$(version_root)/VERSION"
}

# Strict X.Y.Z, all numeric — no "v" prefix, no pre-release suffixes.
version_valid() {
  printf '%s' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# Prints -1, 0 or 1 for $1 vs $2. Numeric per component, so 0.10.0 > 0.9.0
# (which a plain string sort gets wrong). python3 is already required by
# build.sh for the same derivation.
version_cmp() {
  python3 - "$1" "$2" <<'EOF'
import sys
a = [int(x) for x in sys.argv[1].split(".")]
b = [int(x) for x in sys.argv[2].split(".")]
print((a > b) - (a < b))
EOF
}

version_build() {
  python3 -c 'import sys; _, minor, patch = sys.argv[1].split("."); print(int(minor) * 100 + int(patch))' "$1"
}

version_patch() {
  python3 -c 'import sys; print(sys.argv[1].split(".")[2])' "$1"
}

# The `## <version>` section body from NOTES.md (empty when absent).
notes_extract() {
  awk -v v="$2" '$0 ~ ("^## " v "( |$)"){f=1;next} /^## /{f=0} f' "$1/NOTES.md"
}

notes_has_section() {
  [ -n "$(notes_extract "$1" "$2")" ]
}
