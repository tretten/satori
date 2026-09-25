<h1 align="center">Satori</h1>

<p align="center">
  <img src="logo.png" width="128" alt="Satori App Icon">
</p>

<p align="center">
  A small, fast, quiet web browser for the Mac.
</p>

<p align="center">
  <a href="https://github.com/tretten/satori/releases/latest/download/Satori.dmg"><img src="https://github.com/tretten/screenkit/raw/main/download-macos.svg" alt="Download Satori for macOS"></a>
</p>

## Features

- One field: type an address to go there, words to search (DuckDuckGo by default, changeable in Settings › Search). Addresses complete from your own history; nothing is sent anywhere until you press Return.
- Tabs across the top or down the left (`⇧⌘S`), pinned tabs, last session restored instantly, `⌘K` to switch by name.
- Reading mode (`⇧⌘R`), hide-anything (`⇧⌘H`, per site and persistent), picture-in-picture video (`⇧⌘P`, or on its own when you leave a playing tab — off in Settings › Tabs).
- Built-in ad and tracker blocking at the network level, on by default, off per site.
- Passwords saved in the macOS keychain and offered under the field, never auto-filled; one-click import from Chrome, Arc, Dia, Brave, or Edge.
- Chrome extensions on WebKit's own extension engine (macOS 15.4 or later), installable from a Web Store link; unpacked folders for development.
- Bookmarks, history, and downloads as searchable one-keystroke panels; light, dark, or the Mac's own appearance.
- One window — tabs are the only kind of "new" there is.

## Privacy

No account, no sync, no telemetry. Passwords live in the login keychain as ordinary items tagged `Satori`; history, bookmarks, open tabs, and hidden elements are small JSON files under `~/Library/Application Support/Satori/`. Besides the pages you ask for, the only things that leave your Mac are their icons and one small update check a day.

## Install

Requires macOS 14 or later.

Download `Satori.dmg` from [Releases](https://github.com/tretten/satori/releases/latest) and drag `Satori.app` to Applications. Builds are signed with a Developer ID certificate and notarized, so they open with no Gatekeeper warnings.

Updates arrive automatically via Sparkle: once a day the app checks for a newer build, verifies it is signed by tretten, and swaps it in for the next launch. Nothing restarts on its own.

## Build from source

Requires Xcode 16 or later with the Swift 6 toolchain, on macOS 14 or later.

```bash
swift build
./build.sh
```

`swift build` compiles the SwiftPM binary; `./build.sh` assembles a double-clickable `Satori.app` in `build/`, ad-hoc signed so it runs on your own Mac. A self-made build is not notarized and keeps its keychain items apart from a signed Satori's, so the first launch needs right-click → Open (or an allow in System Settings → Privacy & Security).

`./build.sh release dmg` also makes `Satori.dmg` / `Satori.zip` plus the Sparkle `appcast.xml`; `./build.sh release ship` additionally notarizes and staples — that step needs a Developer ID certificate and Apple credentials, so it only really does anything for tretten's own releases.

The marketing version lives in `VERSION` (currently 0.8.0).

## Tech notes

- SwiftUI for everything drawn, AppKit for the few things SwiftUI doesn't reach (the title bar, dragging the window by an empty part of the tab row), WKWebView for pages.
- One `Tab` per page, its web view built lazily — a restored tab costs nothing until you switch to it. Each page runs in WebKit's own content process, as in Safari.
- The ad blocker is a `WKContentRuleList` compiled once at launch and enforced inside WebKit's networking; hidden elements are per-site selector lists injected as a stylesheet at document start.
- Extensions run on `WKWebExtension`, with Satori filling in the Chrome APIs WebKit lacks (bookmarks, history, downloads, notifications, and more).
- Updates ride Sparkle 2, a SwiftPM dependency embedded in the bundle.

## License

MIT. Forked from [driceroland/Search](https://github.com/driceroland/Search); the original name, icon and site remain Office Commun's.
