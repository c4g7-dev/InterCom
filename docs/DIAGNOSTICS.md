# Call diagnostics

InterCom records what happens in a call so that "the share looked blurry" or "nobody heard me" can
be answered from data.

## Overlay

Press **Ctrl+Alt+D** during a call (or enable *Diagnostics* in the call's settings) to show live
statistics for every track: resolution, frame rate, bitrate, codec, the simulcast layer received,
quality limitations, packet loss and round-trip time, together with a few checks:

- microphone publishing with audio
- screen share at the expected resolution
- share audio flowing
- receiving the top layer
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

- an `app_start` record: versions, operating system, Wayland or X11, feature switches, GPU status
- the statistics of every track, every 2 seconds, and the events of the call (join, share start
  and stop, pop-out, fullscreen, device changes)
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
events, network outliers and errors. Given the logs of several participants of the same call, it
sets what one sent against what the others received.

```sh
tools/diag-summary.py alice.jsonl bob.jsonl     # compare both ends
tools/diag-summary.py --json diag-*.jsonl       # machine-readable
tools/diag-summary.py --help                    # thresholds
```
