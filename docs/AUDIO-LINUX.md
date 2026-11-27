# Sharing audio on Linux

On Linux, Lattice can send the sound of any PipeWire or PulseAudio output with a screen share.
This page explains how that works and how to set up a dedicated output for it.

## Why outputs, and not "system audio"

Chromium offers microphones (*sources*) as audio inputs, but never the *monitor* of an output
(*sink*). Its own "system audio" on Linux is the monitor of the default output, which includes the
call itself: the other participants would hear themselves back.

Lattice therefore works on outputs. In the share dialog, **Share audio from** lists:

- **Apps playing into…**: every output, with the applications playing into it right now
- **Input devices**: ordinary inputs, for a mixer or a capture card
- **None**

When you pick an output, Lattice asks the sound server for a source that carries that output's
monitor:

```sh
pactl load-module module-remap-source master=<sink>.monitor \
    source_name=intercom-share-<sink> \
    source_properties="device.description='InterCom share: <sink description>'"
```

The source exists while it is shared and is unloaded afterwards. Lattice only unloads modules it
loaded itself; a source left behind by a crash is recognised by its `intercom-share-` name, used
again the next time that output is shared and removed afterwards. These sources are kept out of
the microphone list.

Shared audio is sent in stereo at 48 kHz, without echo cancellation, noise suppression or
automatic gain.

Requirements: `pactl` (package `libpulse` or `pulseaudio-utils`) and either PipeWire with
`pipewire-pulse`, or PulseAudio.

## Mixing several sources

More than one source can be shared at once, for example a game and a music player on different
outputs. Each source has its own level (0 to 200 %) and mute, and sources can be added, removed
and adjusted while the share is running.

## Avoiding echo

If the call plays into the output you share, the others hear themselves. The dialog marks such an
output ("this call plays here") and warns. Either move the application you want to share to
another output, or move the call. The clean solution is a dedicated output.

## A dedicated output for sharing

Create a virtual output, play what you want to share into it, and share that output.

Temporary, until the sound server restarts:

```sh
pactl load-module module-null-sink sink_name=intercom_share \
    sink_properties=device.description=InterCom-Share-Output

# to hear it yourself as well, loop it to your default output
pactl load-module module-loopback source=intercom_share.monitor latency_msec=20
```

Then move an application to *InterCom-Share-Output* in your volume control (`pavucontrol`, or the
desktop's sound settings), and pick that output in the share dialog.

### Permanent, with pipewire-pulse

To have the output, and a ready-made source for it, on every login, create
`~/.config/pipewire/pipewire-pulse.conf.d/50-intercom-share.conf`:

```
pulse.cmd = [
    # A virtual output to play shared applications into
    { cmd = "load-module"
      args = "module-null-sink sink_name=intercom_share sink_properties=device.description=InterCom-Share-Output" }

    # Its monitor, remapped into a regular source that Chromium lists
    { cmd = "load-module"
      args = "module-remap-source master=intercom_share.monitor source_name=intercom_share_source source_properties=device.description=InterCom-Share" }

    # Optional: also hear it on the default output
    { cmd = "load-module"
      args = "module-loopback source=intercom_share.monitor latency_msec=20" }
]
```

Apply it with `systemctl --user restart pipewire-pulse`.

A source whose description starts with `InterCom-Share` or `InterCom-Screen` is treated like the
ones Lattice makes itself: it is offered as share audio and hidden from the microphone list. If a
remap of an output's monitor already exists, Lattice uses it as it is and leaves it alone.

## Troubleshooting

| Symptom | Check |
| ------- | ----- |
| No outputs in the dialog | `pactl info` must work for your user; install `pactl` |
| "This output's sound could not be made available" | `pactl list short modules`, and the diagnostics log for the `pactl` error |
| Others hear themselves | The call plays into the shared output; use a dedicated one |
| Share audio silent | Is the application really playing into the shared output? `pactl list short sink-inputs` |
| Stale `intercom-share-…` sources | `pactl list short modules`, then `pactl unload-module <index>` |

The diagnostics overlay (Ctrl+Alt+D) shows whether share audio is flowing; see
[DIAGNOSTICS.md](DIAGNOSTICS.md).
