# Call diagnostics

InterCom records what happens in a call so that "the share looked blurry" or "nobody heard me" can
be answered from data.

## Overlay

Press **Ctrl+Alt+D** during a call (or enable *Diagnostics* in the call's settings) to show live
statistics for every track: resolution, frame rate, bitrate, codec, the simulcast layer received,
quality limitations, packet loss and round-trip time, together with a few checks:

- microphone publishing with audio
- screen share at the expected resolution
- my share audio sending, and share audio received from each member who shares a screen
- receiving the top layer, for each member who shares a screen
- no quality limitation

The overlay can also save the frame currently shown as a PNG ("Snapshot") and show a sharpness
test pattern.

## Logs

Every run of the desktop app writes one file:

| Platform | Location                                        |
| -------- | ----------------------------------------------- |
| Linux    | `~/.config/InterCom/logs/diag-YYYYMMDD-HHMMSS.jsonl` |
| Windows  | `%APPDATA%\InterCom\logs\diag-YYYYMMDD-HHMMSS.jsonl` |

*Help > Open diagnostics folder* (also in the tray menu) opens it. Each line is one JSON record:

- an `app_start` record: versions (also the InterCom release, `intercomVersion`), operating
  system, Wayland or X11, feature switches, whether HTTP/3 was on (`quic`), GPU status
- the statistics of every track, every 2 seconds, and the events of the call (join, share start
  and stop, pop-out, fullscreen, device changes)
- for every file sent: `upload_phase` records with the time each step took (decoding, thumbnail,
  blurhash, reading, encrypting, the requests, the event), the file's size and type, and a
  closing record with the total. The file's name is not written
- for every upload request that failed: an `upload_failed` record with the HTTP status (none if
  the server did not answer), the kind of error, the protocol the request went over (h2, h3,
  http/1.1) and whether it was tried again
- `upload_token_refresh` records when an upload renewed the access token: before the upload
  because the token was about to run out (`expiring`) or after the server refused it
  (`refused`), and whether that worked
- for every run of pictures that follow each other closely in a timeline: a `gallery_decision`
  record, written when the run is first drawn and when the decision changes. It says how many
  galleries were made of the run and, for each picture, whether it joined the picture before it
  or why not (`sender`, `gap`, `thread`, `caption`, `reply`, `tile_between`, …), the time since
  the picture before, whether it is a local echo, encrypted, edited, has a caption, the names of
  the fields of its content, and the types of the events that lay between (with whether each has
  a tile). It also says which timeline drew it (`panel`: `legacy`, or `new` for the labs
  "New timeline") and, where pictures are never grouped (search results, notifications, …), why
  (`groupingOff`). No text, file name, URL, user or event ID is written; senders are numbered
- `voice_state` records when mute or deafen changed, with where the change came from (`panel`,
  `hotkey`, `cli`, `call`, `tray`)
- an `update_check` record for every look for an update: how long it took (`ms`, `headersMs`),
  the HTTP status, whether GitHub answered "not modified" (`cached`) and the bytes read
- `updater` records for what the updater did: `check`, `up_to_date` or `update_found`,
  `download_start`, `download_verified` (with the SHA-256), `staged`, `ready`, `install_linux` or
  `install_windows`, `manual` (the install cannot replace itself), `error`
- an `update_on_launch` record for every start: `decision` (`skip`, `start`, `install`), `reason`,
  the `current` and `target` versions, the `ms` the start spent on it, `hidden`, `lastAttempt`
  (`none`, `installed`, `failed`) and `blocked` (a release no longer tried at a start). The
  reasons for `skip` are `unpackaged`, `no-version`, `disabled-by-flag`, `platform`,
  `setting-off`, `auto-check-off`, `not-writable`; for `start` they are `up-to-date`,
  `check-failed`, `check-timeout`, `no-asset`, `failed-before`, `error`, `stalled`, `too-slow`,
  `install-failed`; for `install` it is `ready`. No paths or names
- a `sound_pack` record when the app starts and finds files named like a sound cue in the
  profile's `sounds` directory: `files` (the names that are played) and `skipped`
  (`<name>: not_a_file | empty | too_large | other_format_used`). Never the content
- console warnings and errors

The logs are capped at 200 MB in total; the oldest files are deleted first. Snapshots taken from
the overlay are stored in `logs/snapshots/`.

### What the logs contain

The logs stay on your machine; InterCom does not upload them. Anything that looks like an access
token is removed before a line is written. They do contain room and user identifiers, device
names and, in snapshots, whatever was on screen. Read a log before you attach it to a public
issue.

## Summaries

`tools/diag-summary.py` turns one or more logs into a verdict per feature (Python 3, standard
library only):

```sh
tools/diag-summary.py ~/.config/InterCom/logs/diag-*.jsonl
```

Per file and per call it reports whether the microphone was publishing with audio after the join,
how the screen share was sent and received, whether its audio flowed, pop-out and fullscreen
events, network outliers, uploads (what each took and where the time went) and errors. Given the logs of several participants of the same call, it
sets what one sent against what the others received.

```sh
tools/diag-summary.py alice.jsonl bob.jsonl     # compare both ends
tools/diag-summary.py --json diag-*.jsonl       # machine-readable
tools/diag-summary.py --help                    # thresholds
```
