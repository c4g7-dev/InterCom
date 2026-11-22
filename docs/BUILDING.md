# Building InterCom

InterCom is built from two forks, checked out as submodules of this repository:

| Directory      | Fork of                                                       | Branch     |
| -------------- | ------------------------------------------------------------- | ---------- |
| `element-web`  | [element-hq/element-web](https://github.com/element-hq/element-web) (web + desktop) | `intercom` |
| `element-call` | [element-hq/element-call](https://github.com/element-hq/element-call)               | `intercom` |

The web app bundles the Element Call build from the sibling `element-call` directory, so the two
must sit next to each other, as they do in this repository.

## Requirements

- Linux x64 (the Windows installer is cross-built from Linux)
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

## Configuration

The bundled configuration is `element-web/apps/desktop/intercom/config.json` (brand, themes,
default homeserver). A `config.json` in the profile directory (`~/.config/InterCom/` on Linux,
`%APPDATA%\InterCom\` on Windows) overrides it without a rebuild.

The screen share egress budget is in `element-web/apps/web/res/intercom/element-call-config.json`.

## Releases

`tools/release.sh <version>` builds both targets, collects the assets with checksums, tags the
three repositories and publishes a GitHub release with the notes from `CHANGELOG.md`.
Run `tools/release.sh --help` for the options.

## Keeping up with upstream

Each fork's `intercom` branch sits on an upstream release tag (`git describe --tags` shows which).
To move to a newer release, rebase the branch onto the new tag in each fork, build, and commit the
new submodule pointers here.
