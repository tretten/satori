#!/bin/bash
# Assembles a double-clickable .app around the SwiftPM binary — and, when
# asked, the disk image people install it from and the ZIP the updater
# fetches.
#
#   ./build.sh                 debug-free release build, ad-hoc signed: runs here
#   ./build.sh release dmg     + build/Satori.dmg, build/Satori.zip and
#                                build/appcast.xml, signed with Developer ID
#                                if there is one in the keychain
#   ./build.sh release ship    + both notarised, the DMG stapled
#
# Same shape as the one next door: SwiftPM builds the executable, and a macOS
# app bundle is just a folder with a plist and the binary in the right place —
# plus the Sparkle framework it updates through, embedded in
# Contents/Frameworks.
#
# Updates ride Sparkle 2 (a SwiftPM dependency): build.sh embeds its framework
# and signs it inside-out, and writes the versioned DMG/ZIP plus a signed
# Sparkle appcast.xml that GitHub serves as a release asset. The appcast the
# app reads lives at one address forever (SUFeedURL, below); ./publish.sh
# copies the three constant-named files into the site.
#
# "dmg" lays the disk image's window out with dmgbuild, installed into .build
# on first use (Python 3 and a network, once).
#
# What "dmg"/"ship" needs, once (details in docs/SIGNING.md):
#   - a Developer ID Application certificate in the login keychain
#     (SATORI_SIGN_IDENTITY names it; otherwise the first one found is used)
#   - a notarytool profile: xcrun notarytool store-credentials "satori"
#     (SATORI_NOTARY_PROFILE names it; default "satori")
#   - the Sparkle EdDSA private key in the login keychain, account "satori"
#     (SATORI_SPARKLE_ACCOUNT names it; made once with generate_keys)
#   - the enclosure address is fixed: tretten/satori release v<VERSION> assets
#
# NOTES.md, next to this script, is what's new: one `## <version>` section per
# release, newest first. The section for this version goes into the appcast,
# and from there into Sparkle's update window.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${1:-release}"
STEP="${2:-app}"
APP="build/Satori.app"
NAME="Satori"
# The single source for the marketing version. The build number Sparkle
# compares is derived from it — MINOR*100+PATCH, e.g. 0.8.0 → 800 — so the
# two never drift apart. Monotonic while the major stays 0 and PATCH < 100;
# anything else fails loudly below instead of silently shipping a build
# number Sparkle would ignore.
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="$(python3 -c 'import sys; _, minor, patch = sys.argv[1].split("."); print(int(minor) * 100 + int(patch))' "$VERSION")"
PATCH="$(python3 -c 'import sys; print(sys.argv[1].split(".")[2])' "$VERSION")"
[ "$PATCH" -lt 100 ] || { echo "PATCH must stay below 100 for the Sparkle build number" >&2; exit 1; }
# The oldest macOS this runs on — in the plist, and in the appcast so an
# older Mac is not handed a build it can't open.
MINIMUM="14.0"
# Where the app looks for updates, forever: the Sparkle RSS feed served as a
# GitHub release asset.
FEED="https://github.com/tretten/satori/releases/latest/download/appcast.xml"
# The public half of the Sparkle EdDSA keypair. Public on purpose — kuu keeps
# its own the same way in its Info.plist; the private half stays in the login
# keychain and never appears here.
SUPUBLIC="${SATORI_SPARKLE_PUBLIC_KEY:-a4ERoWdVOkoS1y5JY254w19tGP0ZdK5zzhgVhuB95ZM=}"

swift build -c "$CONFIG"
BINARY=".build/$CONFIG/Satori"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BINARY" "$APP/Contents/MacOS/$NAME"

# Sparkle rides inside the bundle: the XCFramework SwiftPM fetched doubles as
# the embedded copy. The binary links Sparkle as @rpath, and the bundle's
# Frameworks folder is not on its search path — so it is added, once, here.
# (install_name_tool before any signing below; signing seals the result.)
SPARKLE_FW="$(echo .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework)"
[ -d "$SPARKLE_FW" ] || { echo "Sparkle.framework not found — run 'swift package resolve' first" >&2; exit 1; }
cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
chmod -R u+w "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$NAME" 2>/dev/null || true

# Symbols stay out of the app. The linker leaves every function's name and a
# map back to the source in the binary — 15,000 entries, more than half of
# what the app weighed (6.5 MB of binary, 2.7 without them), and nothing the
# app reads while it runs. They are kept beside the build instead, as a dSYM
# that turns the addresses in a crash report back into names (Console, or
# atos -o build/Satori.app.dSYM/Contents/Resources/DWARF/Satori).
if [ "$CONFIG" = "release" ]; then
  rm -rf "$APP.dSYM"
  dsymutil "$BINARY" -o "$APP.dSYM" 2>/dev/null || echo "no dSYM this time" >&2
  strip -x "$APP/Contents/MacOS/$NAME"
fi

# The icon — a Liquid Glass .icon package, compiled by actool into the asset
# catalog (macOS 26) with a raster .icns fallback for older systems.
rm -rf build/IconResources build/AppIcon.icon build/icon-partial.plist
mkdir -p build/IconResources
cp -R Icon/icon.icon build/AppIcon.icon
xcrun actool build/AppIcon.icon \
  --compile build/IconResources \
  --platform macosx \
  --minimum-deployment-target "$MINIMUM" \
  --app-icon AppIcon \
  --standalone-icon-behavior all \
  --output-partial-info-plist build/icon-partial.plist
cp build/IconResources/Assets.car "$APP/Contents/Resources/Assets.car"
cp build/IconResources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.brandkit.satori</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$MINIMUM</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>© tretten · Satori</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- Owning http and https is what lets macOS offer this app as the default
       browser, and what sends a link clicked in Mail here. -->
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>Web address</string>
      <key>CFBundleURLSchemes</key>
      <array><string>http</string><string>https</string></array>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Web page</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSItemContentTypes</key>
      <array><string>public.html</string><string>com.apple.web-internet-location</string></array>
    </dict>
  </array>
  <!-- A browser goes wherever it is pointed, including at http sites and at
       whatever is running on localhost. -->
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <!-- A browser is asked for these by the pages it shows, not by itself. macOS
       still wants a sentence to put in its own prompt, and touching the APIs
       without one is a crash rather than a refusal. -->
  <key>NSCameraUsageDescription</key>
  <string>Websites you visit can ask to use your camera. Satori asks you first, every time, for each site.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Websites you visit can ask to use your microphone. Satori asks you first, every time, for each site.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Files you download are saved to your Downloads folder.</string>
  <!-- Sparkle 2: where updates come from, how often they are looked for, and
       the public key the downloaded build is checked against. -->
  <key>SUFeedURL</key><string>$FEED</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUAutomaticallyUpdate</key><true/>
  <key>SUPublicEDKey</key><string>$SUPUBLIC</string>
</dict>
</plist>
PLIST

# Signing. A Developer ID certificate, when there is one, with the hardened
# runtime Gatekeeper insists on for anything notarised; otherwise ad-hoc,
# which is enough for the app to run on the machine that built it.
IDENTITY="${SATORI_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)}"
# Passkeys need an entitlement Apple grants to browsers on request, and a
# Developer ID provisioning profile that carries it. With the profile next to
# this script, both go in; without it, the app is signed as before, because
# a restricted entitlement with no profile behind it is an app that won't open.
ENTITLEMENTS="Satori.entitlements"
if [ -f "Satori.provisionprofile" ]; then
  cp "Satori.provisionprofile" "$APP/Contents/embedded.provisionprofile"
  ENTITLEMENTS="Satori.passkeys.entitlements"
  echo "passkeys: profile embedded"
fi
# Nested code signs inside-out, towards the app bundle — codesign --deep is
# never used, it can break the nested XPC seals. The Sparkle XPC services and
# helpers first, then the framework, then the app itself.
FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  FWV="$(readlink "$FW/Versions/Current")"
  B="$FW/Versions/$FWV"
  if [ -n "$IDENTITY" ]; then
    NESTED=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
  else
    NESTED=(codesign --force --sign -)
  fi
  for NEST in \
    "$B/XPCServices/Downloader.xpc" \
    "$B/XPCServices/Installer.xpc" \
    "$B/Autoupdate" \
    "$B/Updater.app"; do
    [ -e "$NEST" ] && "${NESTED[@]}" "$NEST"
  done
  "${NESTED[@]}" "$FW"
fi
if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" "$APP"
  echo "signed as: $IDENTITY"
else
  codesign --force --sign - "$APP" 2>/dev/null || true
  [ "$STEP" != "app" ] && echo "no Developer ID certificate found — the DMG will only open on this Mac" >&2
fi
codesign --verify --deep --strict "$APP" && echo "signature verified"

echo "built: $APP ($VERSION, build $BUILD)"
[ "$STEP" = "app" ] && exit 0

# Versioned archives for the GitHub release plus constant-named copies for
# the site: .../releases/download/v<VERSION>/Satori-<VERSION>.zip is the
# Sparkle enclosure (a fixed address per release); .../latest/download/ serves
# the same bytes under names that never change.
DMG_VER="build/$NAME-$VERSION.dmg"
ZIP_VER="build/$NAME-$VERSION.zip"
DMG="build/$NAME.dmg"
ZIP="build/$NAME.zip"

# The disk image: the app beside a shortcut to Applications, on a white
# window with an arrow between them — drawn by Installer/background.swift and
# laid out by Installer/dmg.py through dmgbuild, which writes the Finder's
# layout file itself, so no Finder is scripted and no window opens mid-build.
# dmgbuild is installed into .build the first time, and needs Python 3 and a
# network then; without it the image is the plain one it always was.
ART="build/installer"
rm -rf "$ART" "$DMG_VER" "$DMG"
DMGBUILD=".build/dmgbuild/bin/dmgbuild"
if [ ! -x "$DMGBUILD" ]; then
  { python3 -m venv .build/dmgbuild && .build/dmgbuild/bin/pip install --quiet "dmgbuild==1.6.7"; } >/dev/null 2>&1 || true
fi
if [ -x "$DMGBUILD" ] \
  && swift Installer/background.swift "$ART" >/dev/null \
  && tiffutil -cathidpicheck "$ART/background.png" "$ART/background@2x.png" -out "$ART/background.tiff" >/dev/null 2>&1
then
  "$DMGBUILD" -s Installer/dmg.py \
    -D app="$APP" -D background="$ART/background.tiff" -D icon="$APP/Contents/Resources/AppIcon.icns" \
    "$NAME" "$DMG_VER" >/dev/null
else
  echo "note: no dmgbuild — a plain disk image, without its window laid out" >&2
  STAGE="build/dmg"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG_VER"
  rm -rf "$STAGE"
fi
rm -rf "$ART"
[ -n "$IDENTITY" ] && codesign --force --timestamp --sign "$IDENTITY" "$DMG_VER"
cp "$DMG_VER" "$DMG"
echo "packed: $DMG_VER"

[ "$STEP" = "dmg" ] && NOTARISE=0 || NOTARISE=1
if [ "$NOTARISE" = "1" ]; then
  # Notarisation: Apple looks both over. The ticket is stapled to the image
  # and to the app, so the DMG opens on a Mac that has never seen it even
  # offline — and the ZIP below carries the stapled app, which is what lets
  # Sparkle install it without a Gatekeeper complaint.
  [ -z "$IDENTITY" ] && { echo "can't ship without a Developer ID certificate" >&2; exit 1; }
  xcrun notarytool submit "$DMG_VER" --keychain-profile "${SATORI_NOTARY_PROFILE:-satori}" --wait
  xcrun stapler staple "$DMG_VER"
  cp "$DMG_VER" "$DMG"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP" >/dev/null && echo "staple verified"
fi

# The ZIP is what Sparkle fetches — ditto'd from the app as it will ship, so
# a `ship` run carries the stapled ticket inside.
rm -f "$ZIP_VER" "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP_VER"
cp "$ZIP_VER" "$ZIP"
echo "packed: $ZIP_VER"

# What Sparkle reads: an RSS feed with one item per release, each carrying
# the marketing version (shortVersionString), the integer build Sparkle
# compares (sparkle:version), the oldest macOS it runs on
# (minimumSystemVersion), the enclosure, and the EdDSA signature over the
# archive (sparkle:edSignature). Built by Sparkle's own generate_appcast from
# an isolated staging folder — it would otherwise pick up the DMG as a
# second update — then verified with sign_update before it goes anywhere.
SPARKLE_BIN="$(dirname "$(find .build/artifacts -name generate_appcast -type f 2>/dev/null | head -1)")"
[ -x "$SPARKLE_BIN/generate_appcast" ] || { echo "Sparkle tools not found — run 'swift package resolve' first" >&2; exit 1; }
SPARKLE_ACCOUNT="${SATORI_SPARKLE_ACCOUNT:-satori}"
APPCAST_STAGE="$(mktemp -d)"
cp "$ZIP_VER" "$APPCAST_STAGE/"
NOTES_HTML=""
if [ -f NOTES.md ]; then
  NOTES_MD="$(awk -v v="$VERSION" '$0 ~ ("^## " v "( |$)"){f=1;next} /^## /{f=0} f' NOTES.md)"
  [ -n "$NOTES_MD" ] || NOTES_MD="- Improvements and fixes"
  NOTES_HTML="$(printf '%s\n' "$NOTES_MD" \
    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
    | awk '
        BEGIN{print "<ul>"; buf=""}
        /^[[:space:]]*[-*][[:space:]]+/{
          if (buf != "") print "<li>"buf"</li>"
          line=$0; sub(/^[[:space:]]*[-*][[:space:]]+/,"",line); buf=line; next
        }
        /^[[:space:]]*$/{ next }
        { l=$0; sub(/^[[:space:]]+/,"",l); buf = (buf=="") ? l : buf" "l }
        END{ if (buf != "") print "<li>"buf"</li>"; print "</ul>" }
      ')"
  printf '<h2>Satori %s</h2>\n%s\n' "$VERSION" "$NOTES_HTML" > "$APPCAST_STAGE/$NAME-$VERSION.html"
fi
"$SPARKLE_BIN/generate_appcast" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "https://github.com/tretten/satori/releases/download/v$VERSION/" \
  "$APPCAST_STAGE" >/dev/null
cp "$APPCAST_STAGE/appcast.xml" build/appcast.xml
rm -rf "$APPCAST_STAGE"
"$SPARKLE_BIN/sign_update" --verify build/appcast.xml \
  && echo "appcast verified"
echo "wrote: build/appcast.xml ($VERSION, build $BUILD)"
echo "shipped: $DMG_VER, $ZIP_VER and build/appcast.xml — attach the versioned files and appcast.xml to the GitHub release"
