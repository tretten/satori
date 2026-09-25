# Signing

Release builds are signed with a **Developer ID Application** certificate and
notarized by Apple, so they open everywhere with no Gatekeeper warnings. Team:
`6J5M86XWKN`. The certificate itself is issued only by the team's Account Holder
(A self-signed or ad-hoc signature is not a substitute: ad-hoc changes the cdhash
on every build, and neither survives Gatekeeper without the first-launch bypass.)

Releases are assembled locally by `build.sh`: release build → embed Sparkle →
inside-out Developer ID signature (nested Sparkle code first, app bundle last,
`--options runtime --timestamp`, no `codesign --deep`) → `notarytool --wait` →
`stapler` on the DMG and the app → Sparkle ZIP → EdDSA-signed `appcast.xml` →
GitHub release assets. See the header comment in `build.sh` for the full step list.

## Versions

`VERSION` is the single source for the marketing version (`CFBundleShortVersionString`).
The build number Sparkle compares (`CFBundleVersion`) is derived from it:
`MINOR*100 + PATCH` (0.8.0 → 800), so the two never drift apart. Monotonic while
the major stays 0 and `PATCH` < 100; anything else fails loudly in `build.sh`
instead of silently shipping a build number Sparkle would ignore.

## One-time setup on this Mac

- **Developer ID Application certificate** in the Keychain. Xcode → Settings →
  Accounts → Manage Certificates → `+` → Developer ID Application (or import a
  `.cer` issued via developer.apple.com → Certificates). `SATORI_SIGN_IDENTITY`
  names it when several are present.
- **Notarytool profile** named `satori`:
  ```sh
  xcrun notarytool store-credentials "satori" \
    --apple-id <id> --team-id 6J5M86XWKN --password <app-specific-password>
  ```
  The app-specific password is created at appleid.apple.com → Sign-In and
  Security → App-Specific Passwords. Until the `satori` profile exists, an
  existing profile of the same team can be reused:
  `SATORI_NOTARY_PROFILE=<other-profile>`.
- **Sparkle EdDSA key pair**: the public key is embedded as `SUPublicEDKey` by
  `build.sh` (default compiled in; `SATORI_SPARKLE_PUBLIC_KEY` overrides it);
  the private key lives in this Mac's login Keychain under the account
  `satori` (`SATORI_SPARKLE_ACCOUNT` names it at build time; `build.sh` passes
  it to `generate_appcast` and fails loudly at the appcast step if the key is
  missing). It was made once with Sparkle's tooling:
  ```sh
  ./.build/artifacts/sparkle/Sparkle/bin/generate_keys --account satori
  ```
  Back the private key up at once with
  `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account satori -x <file>`
  and keep that file offline — losing it means existing installs can no longer
  be updated (a different account from other apps on purpose, so keys never mix).
- **`gh`** (`brew install gh`, authenticated) for creating the GitHub release
  and uploading its assets.

Private keys, passwords, and tokens live only in the Keychain and the
environment. Never commit them, never print them.

## Doing a release

Release notes live in `NOTES.md` (one `## <version>` section per release,
newest first, user-facing, English) — `build.sh` reuses the section for the
Sparkle update window, and `script/release.sh --publish` refuses to ship
without it.

```bash
script/bump.sh <version>      # e.g. 0.9.0: validates semver, refuses downgrades, inserts the NOTES.md stub
# ... fill in the new ## <version> notes ...
./build.sh release ship
script/release.sh --publish
```

`bump.sh` keeps `VERSION` the single source of truth (the Sparkle build
number derives from it); `build.sh` signs, notarizes (1–5 minutes), staples,
and writes the versioned DMG + ZIP plus the signed `appcast.xml`;
`release.sh --publish` creates (or reuses) tag `v<VERSION>` in
`tretten/satori`, uploads `Satori-<version>.dmg`, `Satori-<version>.zip`,
and `build/appcast.xml` (as the `appcast.xml` asset — the feed the app reads
at `https://github.com/tretten/satori/releases/latest/download/appcast.xml`)
with `--clobber`, then downloads the ZIP and DMG back, compares byte sizes,
and polls the live feed until it serves the new `sparkle:version`. Nothing
is announced until that passes.

Readiness without touching the network: `script/release.sh` (checks notes,
artifacts, staple, appcast signature, `gh` auth state). Plan without
changing anything: `script/release.sh --publish --dry-run`. Re-verify live
assets after the fact: `script/release.sh --live-check`
(`SATORI_LIVE_RETRIES` / `SATORI_LIVE_WAIT` tune the feed poll).

Variants: no second argument builds and signs the app bundle only;
`release dmg` builds DMG + ZIP + appcast without notarization (local testing
only, never for a public release — Gatekeeper will still warn on download).
`release.sh` accepts `--allow-unstapled` for the same local-only purpose.

## Verifying a build

```bash
codesign --verify --deep --strict --verbose=2 build/Satori.app
.build/artifacts/sparkle/Sparkle/bin/sign_update --verify build/appcast.xml
xcrun stapler validate build/Satori.app
spctl -a -vv build/Satori.app   # expect "accepted" with Developer ID origin
```

After publishing — the same checks `script/release.sh --publish` runs, by
hand (`<v>` = version, `<build>` = `MINOR*100+PATCH`):

```bash
curl -fsSL -o /tmp/Satori-<v>.zip \
  https://github.com/tretten/satori/releases/download/v<v>/Satori-<v>.zip
cmp /tmp/Satori-<v>.zip build/Satori-<v>.zip   # same bytes, else re-upload
curl -fsSL https://github.com/tretten/satori/releases/latest/download/appcast.xml \
  | grep 'sparkle:version="<build>"'           # the new build is live
```
