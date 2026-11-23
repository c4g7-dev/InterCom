# Building InterCom

InterCom for the desktop is built from two forks, checked out as submodules of this repository
(the three of InterCom for Android are under [Android](#android)):

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

InterCom for Android is built from three submodules, each into the next: `matrix-rust-rtc` (the
RTC core, a fork of element-hq/matrix-rust-rtc, in Rust), `element-call-android` (the native call
library, a fork of element-hq/element-call-android) and `element-x-android` (the app, a fork of
Element X Android). Neither fork of the first two is on Maven Central, so each is first published
to the local Maven repository (`~/.m2/repository`), where the next build looks for exactly the
version it names: `matrix_rtc` in `element-call-android/gradle/libs.versions.toml` for the core,
`element_call` in `element-x-android/gradle/libs.versions.toml` for the library.

Requirements:

- JDK 21 (17 is enough for the core), the Android SDK (platforms 34 and 37, build tools 37.0.0)
  with `ANDROID_HOME` set.
- For the core: the Android NDK (`ANDROID_NDK_HOME`, or any version under `$ANDROID_HOME/ndk`), a
  C++ toolchain, [rustup](https://rustup.rs/) with the stable toolchain and the
  `aarch64-linux-android` target, and `cargo-ndk` (`cargo install cargo-ndk`). A distribution's
  own Rust package has no Android target; rustup can be kept apart from it by setting
  `RUSTUP_HOME` and `CARGO_HOME` to directories of their own and putting `$CARGO_HOME/bin` first
  in `PATH` for these commands only. The first build downloads a prebuilt libwebrtc.

```sh
git submodule update --init matrix-rust-rtc element-call-android element-x-android

# 1. The RTC core, into ~/.m2 as io.element.android:matrix-rtc-android:0.5.0-intercom.<n>
(cd matrix-rust-rtc && scripts/build-intercom-android.sh)

# 2. The call library, into ~/.m2 as io.element.android:element-call-*:<version>-intercom.<n>
(cd element-call-android && ./gradlew publishToMavenLocal)

# 3. The app
(cd element-x-android && ./gradlew :app:assembleFdroidRelease)
```

The APK is written to `element-x-android/app/build/outputs/apk/fdroid/release/`. There is one,
for arm64-v8a: the core is built for that ABI only, and an APK for another would have no call
library to load. It is signed with the key given by `INTERCOM_ANDROID_STOREFILE`,
`INTERCOM_ANDROID_STOREPASSWORD`, `INTERCOM_ANDROID_KEYALIAS` and `INTERCOM_ANDROID_KEYPASSWORD`,
or with the debug key when these are not set; an APK signed with another key does not install
over a released one.

The core: `scripts/build-intercom-android.sh` builds the `matrix-rtc-ffi` crate with its `media`
feature in the `mobile-release` profile (about five minutes and 3 GB of disk the first time),
generates the Kotlin bindings from the built library, checks that libwebrtc's JNI symbols are
exported, and packages the AAR. Paths of the build machine are remapped in the library. The
`livekit` crate is a patched copy inside the fork (`vendor/`), so nothing but crates.io and the
libwebrtc download is needed. What the fork changes is in its README.

Checks: in `matrix-rust-rtc`, `cargo test -p matrix-rtc-transport -p matrix-rtc-livekit --lib`
and `cargo test -p matrix-rtc-ffi --features media --lib` (they run on the build machine, and
compile libwebrtc for it); `./gradlew test runQualityChecks` in `element-call-android`; and
`./gradlew :features:callnative:impl:testDebugUnitTest` in `element-x-android`.

Versions: the app is `<Element X version>-intercom.<n>` (`INTERCOM_REVISION` in
`element-x-android/plugins/src/main/kotlin/Versions.kt`, also the last digit of the version
code); the library is `<upstream version>-intercom.<n>` (`VERSION_NAME` in
`element-call-android/gradle.properties`); the core is `<upstream version>-intercom.<n>`
(`INTERCOM_VERSION` in `matrix-rust-rtc/scripts/build-intercom-android.sh`). When the core's
version changes, change `matrix_rtc` in the library's catalog with it, and when the library's
changes, `element_call` in the app's. A release is the tag `android-v<app version>` on this
repository with `InterCom-Android-<app version>-arm64-v8a.apk` and `SHA256SUMS`; the three forks
carry the tag `intercom-android-v<app version>`.

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
