# Release notes

What's new in each Satori, newest first. `build.sh` reads the `## <version>`
section into the Sparkle update window, so write it for people, in English.

## 0.8.1

- Pages now see Safari's user agent, so sites that refused the bare WebKit string (Gmail, Wrike) load.
- Sites can send notifications from ordinary tabs, asked per site; clicking one opens its tab.
- The tab strip takes its colour from the page's own pixels, so themed pages match.
- Tab menu › Tab Color: pick one of up to four colours from the page, remembered per site.
- Slimmer tab strip, password suggestions under the field, download-only tabs close themselves, hovering an off-site link preconnects (Settings › Tabs), and Google's "Switch to Chrome?" prompts are dismissed.

## 0.8.0

The first version. A browser for the Mac with nothing in the way: tabs in a row or down the side, pinned tabs that keep their place, and one field for addresses and searches. Ads are blocked before they load; passwords and passkeys stay in your keychain; anything on a page can be hidden; articles open in a reading mode and videos float. Chrome extensions install from the Chrome Web Store on macOS 15.4 or later — its button says Add to Satori. Tabs you haven't looked at for half an hour sleep and give their memory back. It runs on the engine already in macOS and weighs 2.9 MB.
