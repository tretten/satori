<h1 align="center">Satori</h1>

<p align="center">
  <img src="logo.png" width="128" alt="Satori App Icon">
</p>

<p align="center">
  <b>Small. Fast. Quiet.</b><br>
  A web browser for the Mac that stays out of your way.
</p>

<p align="center">
  <a href="https://github.com/tretten/satori/releases/latest/download/Satori.dmg"><img src="https://github.com/tretten/screenkit/raw/main/download-macos.svg" alt="Download Satori for macOS"></a>
</p>

## One field. That's the whole address bar.

Type an address to go there, words to search (DuckDuckGo by default, changeable in Settings › Search). Addresses complete from your own history and a built-in list of popular sites, and the page you are about to open starts loading while you type (see Privacy). Addresses in other alphabets show as written (пример.рф); lookalike spellings stay in xn-- form, so a fake can't pass for the real site.

**Site colours.** A top bar (or sidebar) wears each site's own colour, remembered. A site you have been to opens in its colour and develops out of it as it loads, and the window under the page wears it too. A ring around the tab's icon shows loading.

## Tabs, the way you work.

**Tabs your way.** Across the top or down the left (`⇧⌘S`). Pinned tabs keep their place. Idle tabs sleep after half an hour, unless you set them to Keep Awake or they hold music or a film paused. The last session comes back instantly. `⌘K` switches by name.

**Spaces.** Up to nine sets of tabs in each window, each with its own name and icon. `⌘1` to `⌘9` switch spaces and `⌥1` to `⌥9` pick tabs (both changeable in Settings), and `⌥⌘←` / `⌥⌘→` step through them. Switch from the button after the traffic lights or with a two-finger swipe across the tabs. `⌘K` finds open tabs in every space.

**Side by side.** Drag a tab onto another tab or onto the page, or give it a shortcut in Settings › Shortcuts. A divider you can drag sets the width.

**Many at once.** `⌘`- or `⇧`-click several tabs to copy, bookmark as one folder, move or close them together. Ten or more tabs unopened for a week are offered for closing.

**Windows.** `⌘N` opens another, each with its own tabs and spaces. Move a tab between windows from its menu or by dragging it out past the window's edge. Quit and reopen, and every window comes back; File › Reopen Closed Window returns the last one you closed.

## Room for the page.

**Focus** (`⌃⌘S`). The tabs and the bar step aside and come back when you point at the edge.

**Reading mode** (`⇧⌘R`). Finds the article on any site, with themes and text size.

**Listen.** Articles read aloud paragraph by paragraph, in the system voice, Apple's voices, or natural voices (Supertonic 3) downloaded only when you pick one.

**Translate Page** (`⇧⌘Y`, or the globe beside Settings). Uses Apple's translator, on your Mac. Right-click the globe to choose the language for a site.

**Picture-in-picture** (`⇧⌘P`). Or on its own when you leave a tab playing video with sound (off in Settings › Tabs). Click a tab's speaker to mute it, or Mute in its menu to keep a whole site silent.

**Hide anything** (`⇧⌘H`). Per site, and it stays hidden.

**Apple Intelligence** (macOS 26). A summary of an article in its language or yours, and history search by meaning.

## Quiet by default.

**Ads and trackers** are blocked at the network level, on by default and off per site. That also drops heavy scripts of no use to the reader and holds embedded YouTube players until you press play.

**Cookie banners** are answered "no" for you, except on the sites you exempt.

**Private tabs** turn the whole window dark while they are in front.

**Copy Address** (`⇧⌘C`) strips tracking tags and click ids. Copy Original Address keeps them, and `⌥⇧⌘C` copies a Markdown link. Share sends a page as its link plus a card with its title, picture and address.

**Passwords** are saved in the macOS keychain and offered under the field, never auto-filled. Sign-in dialogs of password-protected folders can remember theirs. Import from Chrome, Arc, Dia, Brave or Edge in one click.

## Made for the Mac.

**Kensho.** Links from other apps open in a small window first, with the address on top and Open in Satori (`⌘O`) to keep the page. `⌘⌥N` opens an empty one from any app, and `⌘F` finds on its page. Settings › General turns it off.

**Chrome extensions** run on WebKit's own extension engine (macOS 15.4 or later) and install from a Web Store link. Unpacked folders work for development.

**Panels.** Bookmarks, history and downloads open as searchable one-keystroke panels. The downloads list clears itself after the time you choose. Light, dark, or the Mac's own appearance.

**Develop menu**, when you want one (Settings › General): Web Inspector (also `F12`), JavaScript console, page source, empty caches, JavaScript off per tab.

**Local files** open from Finder or a path typed into the address bar. A web app stays one window.

## Privacy

No account, no sync, no telemetry.

### What stays on your Mac

Passwords live in the login keychain as ordinary items tagged `Satori`. History, open tabs, bookmarks, downloads and hidden elements are files under `~/Library/Application Support/Satori/`. They are encrypted with AES-GCM under a key Satori keeps in your login keychain, so other apps and other accounts on the Mac can't read them. Site icons, reading-aloud positions, site colours and muted sites are filed under HMACs made with the same key, so a folder listing doesn't show where you have been. Private tabs add nothing to any of them, except what you hide in one: that is kept so it stays hidden next time, filed under an HMAC of the site's name rather than the name.

### What leaves your Mac

The pages you ask for, their icons, and one small update check a day. Two things happen before you press Return. In a new tab, the address Satori is completing from your history starts loading. And a single word that isn't in the dictionary is looked up in DNS with .com added, to see whether that site exists. Search words are never sent before Return. Translation and summaries run on the Mac with Apple's frameworks. Picking a natural voice downloads its model from Hugging Face once (135 MB).

### Certificates

Many Russian sites, including Sber, Alfa-Bank, T-Bank and Gosuslugi, use certificates from the Russian Ministry of Digital Development, which macOS doesn't trust. Satori trusts that root only for addresses ending in `.ru`, `.su` and `.рф`, so it can't vouch for any other site. You can turn this off in Settings › Privacy & Security.

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

The marketing version lives in `VERSION` (currently 0.10.5).

## Tech notes

- SwiftUI for everything drawn, AppKit for the few things SwiftUI doesn't reach (the title bar, dragging the window by an empty part of the tab row), WKWebView for pages.
- One `Tab` per page, its web view built lazily. A restored tab costs nothing until you switch to it. Each page runs in WebKit's own content process, as in Safari.
- The ad blocker is a `WKContentRuleList` compiled once at launch and enforced inside WebKit's networking; hidden elements are per-site selector lists injected as a stylesheet at document start.
- Extensions run on `WKWebExtension`, with Satori filling in the Chrome APIs WebKit lacks (bookmarks, history, downloads, notifications, and more).
- Updates ride Sparkle 2, a SwiftPM dependency embedded in the bundle.

## License

Satori's own code is MIT (see `LICENSE`). Bundled third-party components retain their own licenses; see `Third-Party-Notices.txt`. The app bundle includes the corresponding license texts.
