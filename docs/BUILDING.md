# Building InterCom

InterCom is built from two forks, checked out as submodules of this repository:

| Directory      | Fork of                                                       | Branch     |
| -------------- | ------------------------------------------------------------- | ---------- |
| `element-web`  | [element-hq/element-web](https://github.com/element-hq/element-web) (web + desktop) | `intercom` |
| `element-call` | [element-hq/element-call](https://github.com/element-hq/element-call)               | `intercom` |

The web app bundles the Element Call build from the sibling `element-call` directory, so the two
must sit next to each other, as they do in this repository.

## Requirements

- Linux x64 (the Windows installer can be cross-built from Linux; releases build it on Windows)
- Node.js 22.18 or newer, and pnpm 12 (`corepack enable` picks the version each fork pins)
- A C/C++ toolchain and Python 3, in case a native module of Element Desktop has no prebuilt
- About 8 GB of free memory for the web build; a few GB of disk for dependencies
- For the Windows installer only: `wine`

## Get the source

```sh
git clone --recurse-submodules https://github.com/c4g7-dev/InterCom.git
cd InterCom
```

The upstream repositories are large. `git clone --recurse-submodules --filter=blob:none` keeps the
download small.

## Linux

```sh
# 1. Element Call, as the package the web app embeds
(cd element-call && pnpm install --frozen-lockfile && scripts/build-intercom-embedded.sh)

# 2. Web app and desktop app
(cd element-web && pnpm install --frozen-lockfile)
element-web/apps/desktop/intercom/build.sh
```

The result is `element-web/apps/desktop/dist/linux-unpacked/` and a `tar.gz` beside it. Start it
with `./run-intercom.sh`.

Options, as environment variables of `build.sh`:

| Variable            | Effect                                                                    |
| ------------------- | ------------------------------------------------------------------------- |
| `INTERCOM_DIST_DIR` | Output directory, e.g. `dist-next` to build beside a running copy         |
| `INTERCOM_TARGET`   | `win` to build the Windows installer                                      |
| `WEBPACK_JOBS`      | Caps the minifier's worker processes when memory is tight                 |
| `NODE_OPTIONS`      | Defaults to `--max-old-space-size=6144`                                   |

`build.sh --skip-web` reuses the web app that is already built in `element-web/apps/web/webapp`.

## Windows installer (from Linux)

```sh
env -u DISPLAY -u WAYLAND_DISPLAY \
    WINEPREFIX="$HOME/.cache/electron-builder/intercom-wine-prefix" \
    INTERCOM_TARGET=win \
    element-web/apps/desktop/intercom/build.sh --skip-web
```

This writes `element-web/apps/desktop/dist-win/InterCom-Setup-x64.exe` (NSIS, per user, x64).
Unsetting `DISPLAY` and `WAYLAND_DISPLAY` keeps wine off the desktop, and the separate
`WINEPREFIX` keeps it out of `~/.wine`.

- The installer is not code signed.
- Search in encrypted rooms needs the Windows prebuilt of the search index, which pnpm leaves out
  on Linux unless asked:
  `pnpm install --frozen-lockfile --os linux --os win32 --cpu x64 --filter element-desktop`.

## Android

InterCom for Android is built from two submodules: `element-call-android` (the native call
library, a fork of element-hq/element-call-android) and `element-x-android` (the app, a fork of
Element X Android). The library fork is not on Maven Central, so it is first published to the
local Maven repository (`~/.m2/repository`), where the app's build looks for exactly the version
named by `element_call` in `element-x-android/gradle/libs.versions.toml`.

Requirements: JDK 21, the Android SDK (platform 37, build tools 37.0.0) with `ANDROID_HOME` set.
The Rust RTC core (`io.element.android:matrix-rtc-android`) comes prebuilt from Maven Central; no
Rust toolchain or NDK is needed.

```sh
git submodule update --init element-call-android element-x-android

# 1. The call library, into ~/.m2 as io.element.android:element-call-*:<version>-intercom.<n>
(cd element-call-android && ./gradlew publishToMavenLocal)

# 2. The app
(cd element-x-android && ./gradlew :app:assembleFdroidRelease)
```

The APKs, one per ABI, are written to `element-x-android/app/build/outputs/apk/fdroid/release/`.
They are signed with the key given by `INTERCOM_ANDROID_STOREFILE`,
`INTERCOM_ANDROID_STOREPASSWORD`, `INTERCOM_ANDROID_KEYALIAS` and `INTERCOM_ANDROID_KEYPASSWORD`,
or with the debug key when these are not set; an APK signed with another key does not install
over a released one.

Checks: `./gradlew test runQualityChecks` in `element-call-android`, and
`./gradlew :features:callnative:impl:testDebugUnitTest` in `element-x-android`.

Versions: the app is `<Element X version>-intercom.<n>` (`INTERCOM_REVISION` in
`element-x-android/plugins/src/main/kotlin/Versions.kt`, also the last digit of the version
code); the library is `<upstream version>-intercom.<n>` (`VERSION_NAME` in
`element-call-android/gradle.properties`). When the library version changes, change `element_call`
in the app's catalog with it. A release is the tag `android-v<app version>` on this repository
with `InterCom-Android-<app version>-arm64-v8a.apk` and `SHA256SUMS`; the forks carry the tag
`intercom-android-v<app version>`.

## Configuration

The bundled configuration is `element-web/apps/desktop/intercom/config.json` (brand, themes,
default homeserver). A `config.json` in the profile directory (`~/.config/InterCom/` on Linux,
`%APPDATA%\InterCom\` on Windows) overrides it without a rebuild.

The screen share egress budget is in `element-web/apps/web/res/intercom/element-call-config.json`.

## Releases

Releases can be built by GitHub Actions ([release.yml](../.github/workflows/release.yml)): the
Linux archive on a Linux runner, the Windows installer on a Windows runner (no wine), from the
submodule commits the tag pins. This needs GitHub Actions to be usable for the repository's account.

```sh
# CHANGELOG.md has a "## <version>" section, the forks' intercom branches are committed
tools/release.sh 1.12.35-intercom.2 --ci
```

That commits the submodule pointers, tags the three repositories and pushes. The workflow then
publishes the GitHub release with the notes from `CHANGELOG.md`, `InterCom-<version>-linux-x64.tar.gz`,
`InterCom-Setup-<version>-x64.exe` and a `SHA256SUMS` over every file of the release; files
that were added to the release by other means are kept. To build a tag again:
`gh workflow run release.yml --ref v<version> -f version=<version>`.

Without `--ci`, `tools/release.sh <version>` builds both targets on this machine (the Windows
installer with wine) and publishes them itself; the releases so far were made this way. Run `tools/release.sh --help` for the options.

## Keeping up with upstream

Each fork's `intercom` branch sits on an upstream release tag (`git describe --tags` shows which).
To move to a newer release, rebase the branch onto the new tag in each fork, build, and commit the
new submodule pointers here.
