# Misia Apps

Public download hub for Misia mobile apps.

- **Website (GitHub Pages):** https://mirozahorak.github.io/misia-apps/
- **APK downloads** are attached to GitHub Releases in this repo.

## Stable download URLs

Each app has a *moving* release tag (`<app>-latest`) that always carries the
newest APK, so links never change:

```
https://github.com/mirozahorak/misia-apps/releases/download/events-latest/misia-events.apk
```

Versioned releases (`events-v1.2.0-6`, …) are kept for history.

## Publishing a new Events APK

From the Flutter repo (`/Users/miro/event`):

```
scripts/publish_android.sh
```

This builds the release APK (if needed), creates a versioned release, and
moves the `events-latest` tag to it.

## Adding another app to the page

1. Add its icon to `assets/`.
2. Copy the commented card template in `index.html` and fill it in.
3. Publish its APK under its own moving tag, e.g. `keyer-latest`.
