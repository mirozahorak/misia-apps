# MISIA.SK APPS

Public download hub for Misia mobile apps.

- **Website (GitHub Pages):** https://mirozahorak.github.io/misia-apps/
- **Short links on nasa.misia.sk:** `https://nasa.misia.sk/app` (this page) and
  `https://nasa.misia.sk/app/android` (direct APK download)
- **APK hosting:** GitHub Releases in this repo — no server storage, no repo
  bloat, GitHub's bandwidth.

## Deploying an app

**[DEPLOYING.md](DEPLOYING.md)** is the full playbook — Android release
readiness (signing, icons, install verification), publishing to this hub,
iOS/TestFlight via fastlane, and the privacy/support pages both stores
require. Start there for any release.

## How it works

The site is a single static `index.html` (no build step) served by GitHub
Pages from the `main` branch. Every push to `main` redeploys it within a
minute or two.

APKs are attached to GitHub Releases. Each app has a **moving tag**
(`<app>-latest`) that always carries its newest APK, which gives a permanent
download URL:

```
https://github.com/mirozahorak/misia-apps/releases/download/events-latest/misia-events.apk
```

Versioned releases (`events-v1.2.0-6`, …) are kept as history.

The page has a **language switcher** (SK / CS / EN). It picks the browser
language on first visit and remembers the choice in `localStorage`.

## Publishing a new Events APK

From the Flutter repo (`/Users/miro/event`):

```bash
scripts/publish_android.sh            # builds the APK if dist/ lacks it
scripts/publish_android.sh --skip-build   # reuse an existing dist/ build
```

The script reads the version from `pubspec.yaml`, then:

1. creates (or updates) the versioned release `events-v<version>-<build>`,
2. recreates the `events-latest` tag with the new APK.

Nothing on the website or nasa.misia.sk needs to change — the stable URL now
serves the new build.

## Editing the website

1. Edit `index.html` (styles are inline in `<head>`, translations in the
   `I18N` object at the bottom).
2. Commit and push to `main`:

   ```bash
   git add -A && git commit -m "…" && git push
   ```

3. GitHub Pages redeploys automatically.

## Adding another app

1. Add its icon to `assets/` (256 px PNG is plenty).
2. Copy the commented card template in `index.html` and fill it in. Give any
   translatable text a `data-i18n="yourKey"` attribute and add `yourKey` to
   all three languages in the `I18N` object.
3. Publish its APK under its own moving tag, e.g.:

   ```bash
   gh release create keyer-latest path/to/misia-keyer.apk \
     --title "Misia Keyer — latest Android" --notes "…" \
     --repo mirozahorak/misia-apps
   ```

   and point the card's download button at
   `…/releases/download/keyer-latest/misia-keyer.apk`.

## Privacy & support pages

Each app has store-required pages served from this repo:

```
<app>/privacy/index.html   → https://mirozahorak.github.io/misia-apps/<app>/privacy/
<app>/support/index.html   → https://mirozahorak.github.io/misia-apps/<app>/support/
```

Use those URLs in App Store Connect and Google Play. See DEPLOYING.md §5.

## Custom domain (optional)

To serve the page as e.g. `apps.misia.sk`: add a `CNAME` DNS record pointing
`apps.misia.sk` → `mirozahorak.github.io`, then set the custom domain in the
repo's Pages settings (or `echo apps.misia.sk > CNAME` and push).
