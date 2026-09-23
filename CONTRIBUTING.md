# Contributing

This is a small, mostly-solo project, reviewed the same way it's written. Contributions are welcome, but a few things make one land faster.

## Before writing code

For anything beyond a small fix, open an issue first describing what you want to change and why. It saves a rewritten pull request later if the direction doesn't fit.

## What tends to get merged

- **Small, focused changes.** One thing per pull request, easy to read start to finish.
- **No new dependencies.** The whole point of this app is staying small; a browser this size doesn't need a package for something Foundation or WebKit already does.
- **Matches the existing style.** Comments here explain *why*, not *what the next line does* — read a couple of existing files before adding a new one. No force-unwraps on anything that can plausibly fail (a network response, a file read, a keychain lookup).
- **Builds clean.** `swift build` with zero warnings you introduced.

## What doesn't

- Rewrites of things that already work, for style reasons alone.
- Anything that phones home, adds analytics, or changes what leaves the app over the network — see the [privacy page](https://github.com/tretten/satori#privacy-concretely) for what that boundary currently is.
- Vendoring Chromium or any other engine. This is a WebKit browser on purpose.

## Review

Pull requests are reviewed by Drice, usually with Claude Code doing a first pass on the diff before a human look. That means a review can be fast even when nobody's watching the repo in real time, but it isn't a guarantee of a same-day answer — this isn't anyone's full-time job. Pinging a stale PR after a couple of weeks is completely fine.

## Reporting a bug

Open an issue with: what you did, what you expected, what happened instead, and your macOS version. A crash log, if there is one, lives at `~/Library/Application Support/Satori/crash.log` — it only ever stays on your Mac unless you paste it into the issue yourself.
