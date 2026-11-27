# Releasing

A release is the built apps and the public repository saying what they do. `tools/release.sh`
(desktop) and `tools/android-release.sh` (Android) do the first; this list is the second. Go
through it before the tag: the release notes and the pictures in them are taken from the tagged
commit.

## Before the tag

1. **`CHANGELOG.md`** has a section `## <version>` (`## Android <version>` for Android): what
   changed, for the people who use the app, the most visible first. It becomes the notes of the
   GitHub release, and the desktop app shows it under "What's new" as text and lists; pictures
   and tables of pictures are left out there, so no sentence may depend on one. Say how each
   change was checked, and what was not.
2. **`README.md`**: if the change is one a user sees, the highlights ("What you get") and the
   comparison table still say what the app does.
3. **`docs/CHANGES-FROM-ELEMENT.md`**: a row for every change in behaviour compared to Element,
   or the changed row, with the version in **Since** (`.13`, `A.8`).
4. The document of the part that changed, when it did:
   [`UPDATES.md`](UPDATES.md) (how the apps update), [`ANDROID.md`](ANDROID.md),
   [`DESIGN.md`](DESIGN.md) (colours, surfaces, arrangement),
   [`DIAGNOSTICS.md`](DIAGNOSTICS.md) (new records or fields),
   [`AUDIO-LINUX.md`](AUDIO-LINUX.md), [`BUILDING.md`](BUILDING.md).
5. **Screenshots** in `docs/images/` for what looks different: new ones, or the old ones
   replaced. Taken from the real interface with made-up people on `example.org` only, never
   from a real account. Look at each before committing it. Pictures in the changelog are linked
   by the tag (`https://raw.githubusercontent.com/c4g7-dev/InterCom/v<version>/docs/images/…`),
   so that old notes keep their pictures.
6. Everything is committed: this repository on `main`, the forks on `intercom`.

`tools/release.sh` warns, and goes on, when `README.md` or `docs/CHANGES-FROM-ELEMENT.md` has
not changed since the last release tag. A release that changes nothing a user sees is the one
case where that is right.

## The release

```sh
tools/release.sh 1.12.35-intercom.13          # builds here, tags, pushes, publishes
tools/release.sh 1.12.35-intercom.13 --ci     # tags and pushes; the workflow builds and publishes
```

`tools/release.sh --help` has the rest; Android is in [BUILDING.md](BUILDING.md#releasing). The
running apps find a release within minutes of its publication, so it is published only with
all its files on it (the script keeps it a draft until then).

## After the push

1. The release has its files under their names (`InterCom-<version>-linux-x64.tar.gz`,
   `InterCom-Setup-<version>-x64.exe`, `SHA256SUMS`), and `sha256sum -c SHA256SUMS` passes on a
   fresh download.
2. `intercomVersion` in the `package.json` inside `resources/app.asar` is the version, on both
   platforms, and neither `app.asar` nor `webapp.asar` holds a path of the build machine.
3. The links and pictures answer 200: the release page, the pictures of its notes, and the
   pictures of every document that changed, as GitHub shows them.
