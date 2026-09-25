#!/bin/bash
# Publishes a shipped build as the GitHub release Sparkle updates from.
#
#   script/release.sh                 local readiness check only (no network)
#   script/release.sh --publish       create/reuse release, upload, verify
#   script/release.sh --live-check    verify the live feed + download sizes
#   script/release.sh --publish --dry-run   print what --publish would do
#   script/release.sh --help
#
# --publish expects ./build.sh release ship to have run first: the versioned
# DMG + ZIP plus build/appcast.xml must exist, the DMG stapled (Gatekeeper
# stays quiet offline), and the appcast EdDSA-signed. It then creates (or
# reuses) release v<VERSION> in tretten/satori, uploads the three assets with
# clobber semantics, downloads the ZIP back and compares byte sizes, and polls
# the live feed until it serves the new sparkle:version.
#
# Why verify after upload instead of trusting gh: the app reads one feed
# address forever (SUFeedURL in build.sh), so a release that uploaded the
# wrong bytes or whose feed still serves the old build silently strands every
# install on the previous version. The checks are the same ones documented in
# docs/SIGNING.md for a manual re-check.
#
# Secrets (gh auth, Apple credentials) live in the keychain and the
# environment. This script never prints them; --dry-run prints commands with
# no values expanded beyond file names and the version.
set -euo pipefail

cd "$(dirname "$0")/.."
. script/lib-version.sh
ROOT="$(version_root)"

REPO="tretten/satori"
FEED="https://github.com/tretten/satori/releases/latest/download/appcast.xml"
# How long the live feed may lag the upload (GitHub CDN): attempts × wait.
LIVE_RETRIES="${SATORI_LIVE_RETRIES:-12}"
LIVE_WAIT="${SATORI_LIVE_WAIT:-10}"

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'
}

PUBLISH=0
LIVE_ONLY=0
DRY_RUN=0
ALLOW_UNSTAPLED=0
for ARG in "$@"; do
  case "$ARG" in
    --help|-h) usage; exit 0 ;;
    --publish) PUBLISH=1 ;;
    --live-check) LIVE_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --allow-unstapled) ALLOW_UNSTAPLED=1 ;;
    *) echo "unknown flag: $ARG (see --help)" >&2; exit 1 ;;
  esac
done
[ "$PUBLISH" = "1" ] && [ "$LIVE_ONLY" = "1" ] && {
  echo "--publish and --live-check are exclusive" >&2; exit 1
}

VERSION="$(version_read)"
version_valid "$VERSION" || { echo "VERSION is not semver: '$VERSION'" >&2; exit 1; }
BUILD="$(version_build "$VERSION")"
TAG="v$VERSION"
DMG_VER="build/Satori-$VERSION.dmg"
ZIP_VER="build/Satori-$VERSION.zip"
APPCAST="build/appcast.xml"

log() { printf '%s\n' "$*"; }
# In dry-run, mutating or network steps are printed, never executed.
run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '+ %s\n' "$*"
  else
    printf '+ %s\n' "$*"
    "$@"
  fi
}
die() { echo "error: $*" >&2; exit 1; }

byte_size() { wc -c < "$1" | tr -d '[:space:]'; }

# --- local gates (read-only; run in every mode incl. --dry-run) -------------

local_checks() {
  log "version: $VERSION (tag $TAG, sparkle build $BUILD)"
  notes_has_section "$ROOT" "$VERSION" \
    || die "NOTES.md has no '## $VERSION' section — script/bump.sh $VERSION makes the stub"
  log "notes: ## $VERSION present"
  for F in "$DMG_VER" "$ZIP_VER" "$APPCAST"; do
    [ -f "$F" ] || die "$F is missing — ./build.sh release ship makes it"
    log "artifact: $F ($(byte_size "$F") bytes)"
  done
  if [ "$ALLOW_UNSTAPLED" = "1" ]; then
    log "note: staple check skipped (--allow-unstapled: local testing only, never for a public release)"
  else
    xcrun stapler validate "$DMG_VER" >/dev/null \
      || die "$DMG_VER is not stapled — ./build.sh release ship staples it"
    log "staple: $DMG_VER validated"
  fi
  SIGN_UPDATE="$(find .build/artifacts -name sign_update -type f 2>/dev/null | head -1 || true)"
  if [ -n "${SIGN_UPDATE:-}" ] && [ -x "$SIGN_UPDATE" ]; then
    "$SIGN_UPDATE" --verify "$APPCAST" >/dev/null \
      || die "$APPCAST failed sign_update --verify — rebuild it with ./build.sh release ship"
    log "appcast: EdDSA signature verified"
  else
    die "sign_update not found — run 'swift package resolve' first"
  fi
}

# --- live verification (network; skipped under --dry-run) --------------------

# $1 = file key for messages, $2 = local path, $3 = download URL
verify_download_size() {
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' RETURN
  LOCAL_SIZE="$(byte_size "$2")"
  log "downloading: $3"
  curl -fsSL -o "$TMP/asset" "$3" \
    || die "download failed: $3"
  REMOTE_SIZE="$(byte_size "$TMP/asset")"
  [ "$LOCAL_SIZE" = "$REMOTE_SIZE" ] \
    || die "$1 size mismatch: local $LOCAL_SIZE != downloaded $REMOTE_SIZE"
  log "size verified: $1 ($LOCAL_SIZE bytes)"
  rm -rf "$TMP"
  trap - RETURN
}

verify_live_feed() {
  log "live feed: $FEED"
  ATTEMPT=1
  while [ "$ATTEMPT" -le "$LIVE_RETRIES" ]; do
    if curl -fsSL "$FEED" 2>/dev/null | grep -q "sparkle:version=\"$BUILD\""; then
      log "live feed serves sparkle:version=\"$BUILD\" (attempt $ATTEMPT)"
      return 0
    fi
    log "attempt $ATTEMPT/$LIVE_RETRIES: new build not live yet — waiting ${LIVE_WAIT}s"
    sleep "$LIVE_WAIT"
    ATTEMPT=$((ATTEMPT + 1))
  done
  die "live feed still lacks sparkle:version=\"$BUILD\" after $LIVE_RETRIES attempts"
}

publish() {
  # Dry-run prints the plan only: no gh calls, no network, no temp files.
  if [ "$DRY_RUN" = "1" ]; then
    log "dry-run: would check gh auth (gh auth status)"
    log "dry-run: would reuse release $TAG if it exists (gh release view), else create it"
    printf '+ %s\n' "gh release create $TAG --repo $REPO --title 'Satori $VERSION' --notes-file <NOTES.md ## $VERSION>"
    run gh release upload "$TAG" --repo "$REPO" --clobber \
      "$DMG_VER" "$ZIP_VER" "$APPCAST"
    log "dry-run: would download ZIP+DMG back, compare byte sizes, and poll the live feed for sparkle:version=\"$BUILD\""
    return 0
  fi
  command -v gh >/dev/null || die "gh not found (brew install gh, then gh auth login)"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated — gh auth login first"
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    log "release $TAG exists — reusing"
  else
    NOTES_TMP="$(mktemp)"
    trap 'rm -f "$NOTES_TMP"' RETURN
    notes_extract "$ROOT" "$VERSION" > "$NOTES_TMP"
    [ -s "$NOTES_TMP" ] || printf 'Satori %s\n' "$VERSION" > "$NOTES_TMP"
    run gh release create "$TAG" --repo "$REPO" \
      --title "Satori $VERSION" --notes-file "$NOTES_TMP"
    rm -f "$NOTES_TMP"
    trap - RETURN
  fi
  # Clobber: re-running --publish replaces stale assets instead of failing
  # on duplicates or, worse, leaving a mix of old and new bytes behind.
  run gh release upload "$TAG" --repo "$REPO" --clobber \
    "$DMG_VER" "$ZIP_VER" "$APPCAST"
  verify_download_size "Satori-$VERSION.zip" "$ZIP_VER" \
    "https://github.com/$REPO/releases/download/$TAG/Satori-$VERSION.zip"
  verify_download_size "Satori-$VERSION.dmg" "$DMG_VER" \
    "https://github.com/$REPO/releases/download/$TAG/Satori-$VERSION.dmg"
  verify_live_feed
  log "published: $TAG ($(byte_size "$ZIP_VER")-byte ZIP verified, feed live)"
}

live_check_only() {
  for F in "$ZIP_VER" "$DMG_VER"; do
    [ -f "$F" ] || die "$F is missing — nothing local to compare the live assets against"
  done
  verify_download_size "Satori-$VERSION.zip" "$ZIP_VER" \
    "https://github.com/$REPO/releases/download/$TAG/Satori-$VERSION.zip"
  verify_download_size "Satori-$VERSION.dmg" "$DMG_VER" \
    "https://github.com/$REPO/releases/download/$TAG/Satori-$VERSION.dmg"
  verify_live_feed
  log "live check passed: $TAG"
}

if [ "$LIVE_ONLY" = "1" ]; then
  [ "$DRY_RUN" = "1" ] && { log "dry-run: would download ZIP+DMG and poll $FEED"; exit 0; }
  live_check_only
elif [ "$PUBLISH" = "1" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    log "version: $VERSION (tag $TAG, sparkle build $BUILD)"
    log "dry-run: would require $DMG_VER + $ZIP_VER + $APPCAST (stapled, appcast verified)"
    log "dry-run: would require NOTES.md '## $VERSION' section"
    publish
  else
    local_checks
    publish
  fi
else
  local_checks
  command -v gh >/dev/null && gh auth status >/dev/null 2>&1 \
    && log "gh: authenticated" \
    || log "note: gh not authenticated — needed only for --publish"
  log "ready: run with --publish to create the release"
fi
