# Deploying a Misia Flutter app — playbook for coding assistants

Canonical, end-to-end instructions for taking a Flutter app in this
organisation from source to users: **Android via this download hub**, **iOS via
TestFlight / App Store Connect**, and the **privacy / support pages** both
stores require.

Written to be executed by a coding assistant with shell access. Every step is a
command you can run and verify — prefer verifying over assuming.

**Reference implementations** (copy from these rather than inventing):

| App | Repo | Package / bundle id |
|---|---|---|
| Misia Akcie/Events | `/Users/miro/event` | `sk.misia.event` |
| Misia Songbook | `/Volumes/DEVEL/songbook/misia_songbook` | `sk.misia.songbook` |

Supporting repos: **hub site** `/Volumes/DEVEL/static/misia-apps` (public,
GitHub Pages) · **backend** `/Volumes/DEVEL/rails/misia71` (prod
`https://nasa.misia.sk`).

> ⚠️ **This repo is public.** Never put passwords, keystores, `.env` contents,
> App Store passwords or API keys in it — including in this file. Refer to
> file *locations* and environment variable *names* only.

---

## 0. Ground rules

1. **Verify, don't assume.** After every deploy-ish action, check the result
   (HTTP status, `apksigner` output, a screenshot, a real install).
2. **Never publish a debug-signed APK.** It triggers install warnings and can
   never be upgraded by a properly signed build.
3. **Never commit** `key.properties`, `*.jks`, `.env`, or `dist/`.
4. **The user deploys the Rails backend and runs App Store submissions.** You
   prepare, build, upload and verify; you do not press "Submit for review".
5. Ask before anything outward-facing that is not part of an explicit request
   (publishing a release, emailing testers, changing store metadata).

---

## 1. Pre-flight: does the app actually work?

Run this before touching signing or stores. It catches the embarrassing
failures — the ones that ship a broken build.

```bash
cd <app-repo>
flutter pub get
flutter analyze                 # must be clean
flutter test                    # must be green
```

### 1.1 Launch it for real (catches what tests cannot)

A release APK that installs but crashes on launch is the classic failure. It
has happened here: `MainActivity` sat in `com.example.<app>` while the manifest
resolved `.MainActivity` against the `sk.misia.<app>` namespace →
`ClassNotFoundException` on every start.

```bash
export ANDROID_HOME=~/Library/Android/sdk; export PATH=$PATH:$ANDROID_HOME/platform-tools
$ANDROID_HOME/emulator/emulator -avd <avd-name> -no-snapshot-save -no-audio -no-boot-anim &
until adb shell getprop sys.boot_completed 2>/dev/null | grep -q 1; do sleep 4; done

flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c
adb shell am start -n <applicationId>/.MainActivity
sleep 12
adb shell pidof <applicationId> && echo RUNNING || echo "CRASHED — check logcat"
adb logcat -d | grep -iE "AndroidRuntime|FATAL" | tail -20
adb exec-out screencap -p > /tmp/launch.png   # then actually look at it
```

Verify the Kotlin package matches the namespace:

```bash
find android/app/src -name "MainActivity*"    # path must mirror the namespace
grep -n "^package" $(find android/app/src -name "MainActivity.kt")
grep -n "namespace" android/app/build.gradle*
```

### 1.2 Walk the primary flows

Drive the app with `adb shell input tap/text/keyevent` and screenshot after each
step. Cover: cold start → main screen, sign-in (if any), the one or two flows
this release changed. Check **every backend call the app makes actually exists** —
a `TODO: confirm endpoint` in config is a red flag:

```bash
grep -rn "TODO\|FIXME" lib/config/ lib/services/ | head
curl -s -o /dev/null -w "%{http_code}\n" -X POST <endpoint>   # 404 = broken feature
```

### 1.3 Localisation sanity

If the app is localised, run it in each locale — untranslated strings are very
visible to users:

```bash
adb root && adb shell setprop persist.sys.locale sk-SK && adb shell stop && adb shell start
# reinstall + screenshot; repeat per locale; restore en-US afterwards
```

---

## 2. Android release readiness

### 2.1 Signing (the #1 cause of install warnings)

Check whether a release keystore exists:

```bash
ls android/key.properties android/app/upload-keystore.jks 2>/dev/null
```

If missing, create one (generate a strong password; store it **only** in the
gitignored `key.properties`; tell the user to back both files up):

```bash
JH="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
"$JH/bin/keytool" -genkeypair -v \
  -keystore android/app/upload-keystore.jks \
  -alias upload -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=<App Name>, OU=Misia, O=Slobodna ludova misia, L=Bratislava, C=SK"
cat > android/key.properties <<EOF
# Google Play upload signing credentials. DO NOT COMMIT.
storePassword=$PASS
keyPassword=$PASS
keyAlias=upload
storeFile=upload-keystore.jks
EOF
chmod 600 android/key.properties
```

> 🔑 **Tell the user, every time:** back up `upload-keystore.jks` +
> `key.properties`. Losing them means never being able to update the app under
> the same identity — users would have to uninstall and reinstall.

`android/app/build.gradle` must read those properties and enable all schemes:

```groovy
signingConfigs {
    release {
        if (keystorePropertiesFile.exists()) { /* keyAlias, keyPassword, storeFile, storePassword */ }
        enableV1Signing = true   // AGP skips v1 automatically when minSdk >= 24
        enableV2Signing = true
        enableV3Signing = true
    }
}
buildTypes {
    release {
        signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug
    }
}
```

### 2.2 Identity and metadata

```bash
grep -n 'android:label' android/app/src/main/AndroidManifest.xml   # human name, not my_app_name
grep -n 'applicationId\|namespace' android/app/build.gradle
grep -n '^version:' pubspec.yaml                                   # x.y.z+build
```

- `android:label` = the name users see under the icon ("Misia Songbook").
- `versionCode` (`+build`) **must increase** for every published build.
- iOS display name: `CFBundleDisplayName` in `ios/Runner/Info.plist`.

### 2.3 Icon (adaptive, brand-matched)

Design from the app's own palette (`lib/theme/`), keep an SVG source in
`assets/icon_source.svg`, and produce three PNGs: full square icon, adaptive
foreground (art scaled to ~75 % so masking never clips it), splash mark.

```bash
rsvg-convert -w 1024 -h 1024 assets/icon_source.svg -o assets/icon.png
# foreground: same art wrapped in <g transform="translate(512,512) scale(0.75) translate(-512,-477)">
```

```yaml
# pubspec.yaml
flutter_launcher_icons:
  android: "launcher_icon"
  ios: true
  image_path: "assets/icon.png"
  remove_alpha_ios: true
  adaptive_icon_background: "#082A23"
  adaptive_icon_foreground: "assets/icon_foreground.png"
```

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create     # if the app uses a native splash
cat android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml   # must exist
```

Then **look at it** on a device home screen — masked to a circle, at real size.

### 2.4 Build and verify the signature

```bash
flutter build apk --release
APKSIGNER=$(ls ~/Library/Android/sdk/build-tools/*/apksigner | tail -1)
"$APKSIGNER" verify --verbose build/app/outputs/flutter-apk/app-release.apk | grep -E "Verifies|v[123] scheme"
"$APKSIGNER" verify --print-certs build/app/outputs/flutter-apk/app-release.apk | grep "certificate DN"
```

Expected: `Verifies`, **v2 = true, v3 = true**, and a DN that is **not**
`CN=Android Debug`. (v1 false is correct when `minSdk >= 24`.)

### 2.5 What the installer will show the user

```bash
AAPT=$(ls ~/Library/Android/sdk/build-tools/*/aapt2 | tail -1)
"$AAPT" dump badging build/app/outputs/flutter-apk/app-release.apk \
  | grep -E "^package:|application-label:|uses-permission|native-code"
```

Checklist for a warning-free sideload:

- [ ] `targetSdkVersion` current (36 today); **≥ 24 is mandatory** or Android 14+ refuses to install
- [ ] No unnecessary permissions — every extra one becomes a user-facing prompt
- [ ] Release-signed (§2.4)
- [ ] Real install on a **clean** device: `adb uninstall <id>; adb install <apk>` → `Success`
- [ ] App launches and works after that install

Unavoidable, and worth telling the user rather than chasing: Android always
asks permission for the *browser* to install unknown apps, and Play Protect may
show a one-time scan notice for apps distributed outside Play.

> **Signature-mismatch trap:** anyone with an older *debug-signed* build gets
> "App not installed". They must uninstall first. Mention this in release notes
> the first time an app switches to release signing.

---

## 3. Publishing to the download hub

APKs are hosted as **GitHub Releases** on `mirozahorak/misia-apps`. Each app has
a moving `<app>-latest` tag so the public URL never changes, plus versioned
`<app>-v<version>-<build>` releases for history.

### 3.1 One command

```bash
cd <app-repo>
scripts/publish_android.sh              # builds if dist/ lacks the current version
scripts/publish_android.sh --skip-build # reuse an existing dist/ build
```

It: builds → **refuses to publish a debug-signed APK** → creates the versioned
release → moves `<app>-latest` → stamps version + date/time onto the hub page →
pushes the site (Pages redeploys in ~1 min).

### 3.2 Adding a *new* app to the hub

1. Copy `scripts/publish_android.sh` from an existing app; set `ASSET_NAME`
   (`misia-<app>.apk`) and `APP_KEY` (`<app>`).
2. Icon → hub: `rsvg-convert -w 256 -h 256 assets/icon_source.svg -o
   /Volumes/DEVEL/static/misia-apps/assets/<app>-icon.png`
3. Card in `misia-apps/index.html`: copy an existing `<section class="card">`.
   Every translatable string needs `data-i18n="key"`, and the key must be added
   to **all three** languages in the `I18N` object (sk / cs / en). Include the
   version stamp the publish script writes:
   ```html
   <strong id="<app>-version">1.0.0 (1)</strong>
   · <span id="<app>-version-date">—</span>
   ```
4. Privacy + support pages (§5).
5. Backend download route (§3.3).

### 3.3 Counted download link (backend)

The site links to `nasa.misia.sk/app/<app>/android`, which logs the download and
redirects to GitHub. Register the app in
`app/controllers/app_downloads_controller.rb`:

```ruby
APKS = {
  "events"   => ".../releases/download/events-latest/misia-events.apk",
  "songbook" => ".../releases/download/songbook-latest/misia-songbook.apk"
}.freeze
```

Routes already handle `/app/:app/android`; `/app/android` is the legacy events
alias. **The user must deploy the backend** before a new app's link works.

Verify after their deploy:

```bash
curl -s -o /dev/null -w "%{http_code} -> %{redirect_url}\n" https://nasa.misia.sk/app/<app>/android
curl -sI -o /dev/null -w "%{http_code}\n" -L -r 0-0 "<the github URL it redirects to>"   # 200/206
```

### 3.4 Download statistics

- `./stats.sh` in the hub repo — server counts (authoritative) + GitHub counts (rough)
- `bin/rails app:downloads` on the server — per-app totals and per-day history
- `https://nasa.misia.sk/app/stats` — JSON

GitHub's per-asset counter **resets on every publish** (the `-latest` asset is
recreated) and is cached; always trust the server numbers.

---

## 4. iOS: TestFlight and App Store Connect

### 4.1 fastlane

fastlane is the **Homebrew** install — there is no `Gemfile`, so
`bundle exec fastlane` fails with *"Could not locate Gemfile"*. Run it plain:

```bash
cd /Users/miro/event
fastlane beta          # flutter build ipa + upload_to_testflight
```

Credentials come from the repo-root `.env` (gitignored, auto-loaded by the
Fastfile via dotenv): `APP_STORE_APPLE_ID`, `APP_STORE_CONNECT_TEAM_ID`,
`FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`.

Bump `version:` in `pubspec.yaml` first. **A version already submitted for App
Store review must keep its number** — ship the next TestFlight build under a new
version (e.g. 1.1.0 in review → upload 1.2.0). Uploading new TestFlight builds
never disturbs a submission in review.

### 4.2 After the upload: processing, groups, testers

Apple takes ~5–30 min to process. Then assign the build to beta groups via
Spaceship. Note: the app lives under ASC team **121616402**, which is *not* the
`APP_STORE_CONNECT_TEAM_ID` in `.env` — set `FASTLANE_ITC_TEAM_ID=121616402`,
and run Ruby with Homebrew fastlane's gems:

```bash
FASTLANE_ITC_TEAM_ID=121616402 \
GEM_HOME="$HOME/.local/share/fastlane/4.0.0" \
GEM_PATH="$HOME/.local/share/fastlane/4.0.0:/opt/homebrew/Cellar/fastlane/<ver>/libexec" \
PATH="/opt/homebrew/opt/ruby/bin:$PATH" ruby script.rb
```

```ruby
Spaceship::ConnectAPI.login("miro@misia.sk", nil, use_portal: false, use_tunes: true)
app   = Spaceship::ConnectAPI::App.find("sk.misia.event")
build = Spaceship::ConnectAPI::Build.all(app_id: app.id, version: "1.2.0", build_number: "6").first
Spaceship::ConnectAPI.add_beta_groups_to_build(build_id: build.id, beta_group_ids: [group.id])
```

Expected quirks: assigning the **internal** group fails ("Cannot add internal
group to a build") — internal testers get builds automatically. Re-inviting a
tester who already accepted fails with "invitation already accepted" — that is
success, not an error.

### 4.3 Store metadata

The `asc` CLI (Homebrew) is authenticated and handles localisations,
categories, age rating, pricing, review details and screenshots:

```bash
asc validate --app <app-id> --version-id <version-id>     # readiness report
```

App Privacy labels are **web-UI only** — the user must fill those in.

Screenshots: iOS release/profile builds don't run on simulators. Use a **debug**
build pointed at production:

```bash
flutter run -d <simulator-udid> --dart-define=API_BASE_URL=https://nasa.misia.sk
```

To skip onboarding, write `flutter.onboarding_completed` (bool) into the app
container's `Library/Preferences/<bundle-id>.plist` with Python `plistlib` —
kill `cfprefsd` first; `simctl spawn defaults write` does **not** work.

---

## 5. Privacy & support pages (required by both stores)

App Store Connect requires a **privacy policy URL** (and a support URL); Google
Play requires a privacy policy URL for every app. Host them on this hub so they
are independent of the Rails deploy:

```
misia-apps/<app>/privacy/index.html   → https://mirozahorak.github.io/misia-apps/<app>/privacy/
misia-apps/<app>/support/index.html   → https://mirozahorak.github.io/misia-apps/<app>/support/
```

Copy an existing pair and edit; they share `assets/legal.css`. Link both from
the app's card in `index.html`.

**Write what the app actually does — verify it in the code first.** Read
`lib/services/`, `lib/config/` and the manifest permissions; do not copy another
app's claims. A policy must state:

- what data is collected (and that browsing without an account collects none)
- what is stored only on the device (preferences, favourites, cache)
- what leaves the device, when, and to where (HTTPS)
- that there is no advertising / profiling / selling of data — if true
- children's data, if the app can carry any
- how to request deletion, plus a contact e-mail
- a short summary in Slovak (`<p class="sk">`)

Store form answers follow from the same audit: an app with no account, no
analytics and no ads declares **"No data collected"**; an app that sends a
contact form declares that contact info is collected and used for support only.

Verify after pushing:

```bash
for u in <app>/privacy <app>/support; do
  curl -s -o /dev/null -w "$u %{http_code}\n" https://mirozahorak.github.io/misia-apps/$u/
done
```

---

## 6. Release checklists

### Android → hub

- [ ] `flutter analyze` clean · `flutter test` green
- [ ] Debug build launches; primary flows walked with screenshots
- [ ] No `TODO` endpoints; every backend call returns non-404
- [ ] `versionCode`/`versionName` bumped in `pubspec.yaml`
- [ ] `android:label` is the human app name
- [ ] Adaptive icon regenerated and eyeballed on a launcher
- [ ] Release keystore present; **user reminded to back it up**
- [ ] `apksigner`: Verifies, v2+v3, DN is not `CN=Android Debug`
- [ ] targetSdk current, minSdk ≥ 24, no surprise permissions
- [ ] Clean-device install → `Success`, app launches
- [ ] `scripts/publish_android.sh` run; hub page shows new version + date
- [ ] Privacy + support pages exist and return 200
- [ ] Backend deployed if a new `/app/<app>/android` route was added
- [ ] Download link tested end-to-end from the live site

### iOS → TestFlight

- [ ] Version bumped; not colliding with a version in review
- [ ] `fastlane beta` → "Successfully uploaded"
- [ ] Build processed (state VALID) and assigned to the external group
- [ ] Testers notified (or told why no new invite was sent)
- [ ] Privacy policy + support URLs set in ASC
- [ ] `asc validate` clean before the user submits

### Report back to the user

State plainly: what shipped, what was verified and how, what is **still
theirs to do** (backend deploy, App Store submit, keystore backup), and any
bug found along the way — including ones you did not fix.

---

## 7. Known traps (learned the hard way)

| Symptom | Cause | Fix |
|---|---|---|
| App installs, white screen | Release resource shrinker stripped a drawable referenced only by name from Dart | `res/raw/keep.xml` with `tools:keep`; never let init failures block `runApp` |
| Crash on launch, `ClassNotFoundException` | `MainActivity` package ≠ manifest namespace | Move the Kotlin file to match the namespace |
| Login succeeds but UI stays put | Screen was **pushed**; go_router's redirect does not dismiss pushed pages | Navigate explicitly on the auth-success listener |
| "Login does not work" for many users at once | Rate limiter keyed by IP only; a whole venue shares one NAT IP | Key by IP + email (and IP + token for writes) |
| Edits vanish until pull-to-refresh | Wrote to one cache, screen reads another | Write the server response to the store the provider actually reads |
| Maps/links do nothing on Android 11+ | `canLaunchUrl` false without a `<queries>` entry | Add `<intent><action VIEW/><data scheme="https"/></intent>`; don't gate on `canLaunchUrl` |
| GitHub download count stuck at 0 | Moving `-latest` asset recreated each publish; counts are cached | Trust the server counter (`/app/stats`) |
| Dates stay English in a localised app | Bare `DateFormat` uses the intl default | Set `Intl.defaultLocale` from the resolved locale in `localeResolutionCallback` |
