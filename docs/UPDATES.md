# Updates

Both apps update themselves from the [releases of this repository](https://github.com/c4g7-dev/InterCom/releases).
The desktop releases are tagged `v<version>`, the Android ones `android-v<version>`; each app
takes only its own. Drafts are never offered, pre-releases only where asked for.

The builds are not code signed. A download is checked against the `SHA256SUMS` of the release
it comes from, which catches a broken download but is no proof of who made it.

## Desktop

| Settings → InterCom | The status bar over the user panel |
| --- | --- |
| ![The InterCom settings tab with the update switches](images/settings-updates.png) | ![Downloading 1.12.35-intercom.11 · 41 %](images/update-bar.png) |

**When it looks.** At every start, before the window opens, and 30 seconds after the start and
every six hours while it runs. A check asks GitHub for the last five releases, sends the ETag of
the last answer (an unchanged list costs no download) and gives up after 8 seconds.

**At a start.** If a newer release is out, it is downloaded, checked, installed, and InterCom
comes up as the new version, with a small window saying what it is doing ("Checking for
updates…", "Downloading update · 42 %", "Installing…", "Starting…"). GitHub gets two seconds, a
start that finds nothing three at most. Offline, or when the download stalls (20 s without
progress, 5 minutes in all), InterCom starts as it is and offers the update in the app. With
`--hidden` it does the same without the window. A release that did not install at a start is
not tried at a start again; it stays behind *Restart to update*.

**While it runs.** A new release is downloaded and checked, then the status bar over the user
panel and a toast offer *Restart to update* (also in the tray menu, and as a dot on the settings
button of the user panel). Nothing is installed before that click. The bar shows each step
("Downloading 1.12.35-intercom.11 · 42 % · 78 MB / 186 MB · 12 MB/s", "Verifying checksum…",
"Unpacking…", "… is ready" with *Restart*); a click on it lists the last steps with their times.
An error stays, with *Retry* and *Details*.

**Settings → InterCom** has the version, *Check for updates automatically*, *Update
automatically on launch* (it needs the first; both on by default), *Check now* and the release
notes. Both switches are kept in `<profile>/intercom-updater.json`.

**Linux** (the unpacked `tar.gz`). The new archive is unpacked beside the install directory as
`<dir>.new`; on restart `<dir>` becomes `<dir>.old` (an older backup is deleted) and `<dir>.new`
becomes `<dir>`. To go back: quit, and rename `<dir>.old` to `<dir>`. The directory and the one
above it must be writable; where they are not (a package under `/opt`, an AppImage), nothing is
downloaded and the app points to the release page. InterCom then starts again with the options
it was started with.

If you start InterCom through a script of your own, let it export `INTERCOM_LAUNCHER` (its own
path), so that an update starts the script again rather than the program behind it, and
optionally its arguments, one per line, in `INTERCOM_LAUNCHER_ARGS`:

```sh
INTERCOM_LAUNCHER="$(readlink -f "$0")"
INTERCOM_LAUNCHER_ARGS="$(printf '%s\n' "$@")"
export INTERCOM_LAUNCHER INTERCOM_LAUNCHER_ARGS
exec /path/to/intercom/intercom "$@"
```

`run-intercom.sh` in this repository does this.

**Windows** (the per-user installer). The installer is downloaded to `%APPDATA%\InterCom\updates`,
checked, and run silently on restart; it starts InterCom again. A start with `--hidden` that
updates comes back with its window shown.

**Never updates:** a build that is not a release, an unpackaged run, and a run with
`--no-update`.

**Logged:** every check is an `update_check` record in the diagnostics log, every step of the
updater an `updater` record, every start an `update_on_launch` record. See
[DIAGNOSTICS.md](DIAGNOSTICS.md).

### Old installs

- 1.12.35-intercom.4 and older have no updater: install a newer release by hand once.
- On Linux, 1.12.35-intercom.5 to .9 cannot install updates by themselves (their updater failed
  on the install directory): install 1.12.35-intercom.10 or newer by hand once. Windows was not
  affected.

## Android

Settings → **InterCom updates**:

- **Look for updates** (on): every time the app is opened, at most once in half an hour, on any
  connection. The check is a request to GitHub for this repository's releases; nothing about you
  or your account is in it.
- **Install updates automatically** (on): a release is downloaded as soon as it is found, on
  Wi-Fi unless **Use mobile data** is on, and installed right away. It never interrupts a call:
  it waits until the call is over.
- **Offer pre-releases** (off), **Check now**, **Download and install**.

With *Install updates automatically* off, a dialog says "InterCom <version> is available", with
*Update now*, *Later* (24 hours for that release) and *Release notes*. *Update now* downloads on
whatever connection there is, mobile data included.

What happens on the phone:

1. The first update needs you once: Android asks to allow InterCom to install apps
   ("Install unknown apps"), and may ask to confirm.
2. On Android 12 or newer, later updates install without a question; on older versions Android
   asks for one tap (from a notification when InterCom is not on screen).
3. Android closes the app while it is replaced and does not let it reopen itself: a
   notification says "InterCom was updated", and a tap on it opens the app.

An APK is installed only if it has the SHA-256 the release names and is signed with the key of
the installed app; anything else is deleted and the settings say why. When Android refuses an
update, the screen shows which of its reasons it gave and the system's own message. An automatic
installation that Android refused is not tried again by itself; the release is offered in the
dialog instead.

On Samsung Galaxy phones, **Auto Blocker** stops these installs too: see
[ANDROID.md](ANDROID.md#samsung-auto-blocker).

The updater came with 26.11.1-intercom.4 and works as described here from 26.11.1-intercom.5.
Every release is signed with the same key, so a newer APK also installs over the old one by
hand.
