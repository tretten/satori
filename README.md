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

- One field: type an address to go there, words to search (DuckDuckGo by default, changeable in Settings › Search). Addresses complete from your own history and a built-in list of popular sites, and the page you are about to open starts loading while you type (see Privacy).
- Tabs across the top or down the left (`⇧⌘S`), pinned tabs, last session restored instantly, `⌘K` to switch by name, and two tabs side by side (`⌘\`) with a divider you can drag.
- Reading mode (`⇧⌘R`) that finds the article on any site, with themes and text size, hide-anything (`⇧⌘H`, per site and persistent), picture-in-picture video (`⇧⌘P`, or on its own when you leave a playing tab, off in Settings › Tabs).
- Translate Page (`⇧⌘Y`) with Apple's translator, on your Mac.
- Listen: articles read aloud paragraph by paragraph, in the system voice, Apple's voices, or natural voices (Supertonic 3) downloaded only when you pick one.
- With Apple Intelligence on (macOS 26): a summary of an article in its language or yours, questions about the page (`⇧⌘A`), history search by meaning, and plain explanations of pages that fail to load.
- Share a page as its link plus a card with its title, picture and address.
- Built-in ad and tracker blocking at the network level, on by default, off per site, which also drops heavy scripts of no use to the reader and holds embedded YouTube players until you press play. Cookie banners are answered "no" for you, except on the sites you exempt.
- Passwords saved in the macOS keychain and offered under the field, never auto-filled; sign-in dialogs of password-protected folders can remember theirs; one-click import from Chrome, Arc, Dia, Brave, or Edge.
- Chrome extensions on WebKit's own extension engine (macOS 15.4 or later), installable from a Web Store link; unpacked folders for development.
- Bookmarks, history, and downloads as searchable one-keystroke panels; light, dark, or the Mac's own appearance.
- A Develop menu when you want one (Settings › General): Web Inspector, page source, empty caches, JavaScript off per tab.
- One window: tabs are the only kind of "new" there is.

## Privacy

No account, no sync, no telemetry.

### What stays on your Mac

Passwords live in the login keychain as ordinary items tagged `Satori`. History, open tabs, bookmarks, downloads and hidden elements are files under `~/Library/Application Support/Satori/`. They are encrypted with AES-GCM under a key Satori keeps in your login keychain, so other apps and other accounts on the Mac can't read them. Site icons, reading-aloud positions and site background colours are filed under HMACs made with the same key, so a folder listing doesn't show where you have been.

When you open a site's front page, Satori keeps a picture of it to show for a moment the next time it loads. The picture is shrunk to 700 points wide and blurred before it is saved, so nothing on it can be read. It is kept in `~/Library/Caches`, which Time Machine skips, and deleted after a day. Private tabs keep none of this.

### What leaves your Mac

The pages you ask for, their icons, and one small update check a day. Two things happen before you press Return. In a new tab, the address Satori is completing from your history starts loading. And a single word that isn't in the dictionary is looked up in DNS with .com added, to see whether that site exists. Search words are never sent before Return. Translation, summaries and answers about a page run on the Mac with Apple's frameworks. Picking a natural voice downloads its model from Hugging Face once (135 MB).

### Certificates

Many Russian sites, including Sber, Alfa-Bank, T-Bank and Gosuslugi, use certificates from the Russian Ministry of Digital Development, which macOS doesn't trust. Satori trusts that root only for addresses ending in `.ru`, `.su` and `.рф`, so it can't vouch for any other site. You can turn this off in Settings › Privacy.

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

`./build.sh release dmg` also makes `Satori.dmg` / `Satori.zip` plus the Sparkle `appcast.xml`; `./build.sh release ship` additionally notarizes and staples. That step needs a Developer ID certificate and Apple credentials, so it only really does anything for tretten's own releases.

The marketing version lives in `VERSION` (currently 0.8.8).

## Tech notes

- SwiftUI for everything drawn, AppKit for the few things SwiftUI doesn't reach (the title bar, dragging the window by an empty part of the tab row), WKWebView for pages.
- One `Tab` per page, its web view built lazily. A restored tab costs nothing until you switch to it. Each page runs in WebKit's own content process, as in Safari.
- The ad blocker is a `WKContentRuleList` compiled once at launch and enforced inside WebKit's networking; hidden elements are per-site selector lists injected as a stylesheet at document start.
- Extensions run on `WKWebExtension`, with Satori filling in the Chrome APIs WebKit lacks (bookmarks, history, downloads, notifications, and more).
- Updates ride Sparkle 2, a SwiftPM dependency embedded in the bundle.

## License

MIT. Forked from [driceroland/Search](https://github.com/driceroland/Search); the original name, icon and site remain Office Commun's.
