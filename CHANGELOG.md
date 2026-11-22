# Changelog

Versions are `<Element Web version>-intercom.<n>`: the upstream release InterCom is based on,
followed by the InterCom revision.

## Android 26.11.1-intercom.2

`android-v26.11.1-intercom.2`, based on Element X Android 26.11.1. The call library is now
InterCom's own fork of element-call-android 0.1.2 (`0.1.2-intercom.1`), a new submodule.

- **Phone audio in a screen share.** The sheet that now opens when you tap the share button has
  a "Share phone audio" switch, on by default: viewers hear what the phone plays (music, videos,
  games) as the share's own audio, with its own volume slider on the desktop. Android 10 or
  newer. Apps that forbid being recorded, and phone calls, are silent in it by Android's design.
- **Sharper screen share.** The screen is sent at its own resolution, up to 1440p on the long
  edge, at 30 fps, as a single layer of up to 10 Mbit/s (about 8 for a 1080 × 2400 screen)
  instead of 1280 px at 15 fps with simulcast. 1080p, 720p and 15 fps can be chosen in the same
  sheet; the choice is remembered. VP8 unless another codec is chosen in the developer options.
- **Equal grid layout.** Call settings → Preferences → Layout → Equal grid: every tile the same
  size, cameras, avatars and shared screens alike, shares uncropped, nothing in the spotlight,
  as large as the screen allows upright or sideways. Remembered. Double tap still fills the
  screen with one tile.
- The version name carries the InterCom revision and the version code grows with it.
- Known limitations: the phone audio is sent with the RTC core's default audio settings (Opus at
  up to 48 kbit/s, with silence suppression; stereo is not negotiated), not yet at music
  bitrate, which needs a change in the Rust core; a share received on the phone has no sound;
  no volume control per tile; a 1440p or 1080p share at 30 fps is demanding for a phone;
  arm64 only; not tested on a device before release.

## Android 26.11.1-intercom.1

First release of InterCom for Android (`android-v26.11.1-intercom.1`), based on Element X
Android 26.11.1 and element-call-android 0.1.2. Android versions are
`<Element X Android version>-intercom.<n>`.

- Own name, icon and application id (`com.c4g7.intercom.android`); installs next to Element X.
- Native MatrixRTC calls by default instead of the Element Call web view, with screen sharing
  (1280 px long edge, 15 fps: the preset of element-call-android, which has no option for it).
- OAuth client registration that Matrix Authentication Service accepts for the app's own
  redirect scheme.
- Push notifications through UnifiedPush only (no Firebase); a distributor app such as ntfy is
  required.
- No analytics, no bug report upload.
- Known limitations: the phone's audio is not part of a screen share; arm64 only; no automatic
  updates; not tested on a device before release.

## 1.12.35-intercom.2

A maintenance release: one visual fix and new release tooling. Calls, audio and layout are the
same as in 1.12.35-intercom.1.

### Fixes

- Sign-in page: the side panel with the logo was a flat grey in the InterCom Dark theme. The
  sign-in card is now one flat surface in the theme's colours, with a hairline border.

### Builds

- New: a GitHub Actions workflow that builds a release from the tagged source, the Linux archive
  on Linux and the Windows installer on Windows, and publishes it. The files of this release
  were still built like those of the first one: on a Linux machine, the Windows installer
  cross-built with wine. It is not code signed.
- The two source forks say at the top of their README that they are the InterCom forks.

### Unchanged since 1.12.35-intercom.1

For reference, the call features of the first release, all in this build as well:

- Volume above 100 % per participant and per screen share, with the fixes for it: the volume no
  longer jumps when a tile comes back below 100 %, and deafen silences boosted tiles too.
- Equal grid layout: every tile the same size, screen shares included.
- Linux: the share dialog lists the audio outputs (sinks) and the applications playing into
  them; several sources are mixed into the share and can be changed while sharing.
- Shortcuts in a call (Ctrl+Shift+M, Ctrl+Shift+D, Ctrl+Shift+V) and the same actions from the
  command line (`--toggle-mute`, `--toggle-deafen`, `--toggle-camera`, `--leave-call`); global
  on Windows while a call is on.

## 1.12.35-intercom.1

First public release. Based on Element Web / Desktop 1.12.35 and Element Call 0.29.0-rc.2.

### Calls and screen share

- Screen share at native resolution ("Auto": native, capped at 1440p; "Native": no cap), with
  presets for text (sharp, 30 fps, resolution never given up), motion (60 fps) and low bandwidth.
- Higher screen share bitrates (about 10 Mbps at 1080p, 15 Mbps at 1440p), kept within a
  configurable server egress budget that is shared between the viewers.
- Codec choice for screen share (Auto, VP9, AV1 where every viewer can decode it), custom bitrate
  and frame rate under "Advanced".
- The content hint asked for is kept for every codec, and video keeps flowing while the window is
  in the background.
- Fix: the microphone is no longer muted right after joining a call.
- Shortcuts in a call: Ctrl+Shift+M mutes, Ctrl+Shift+D deafens, Ctrl+Shift+V toggles the camera.
  The same actions from the command line (`intercom --toggle-mute`, `--toggle-deafen`,
  `--toggle-camera`, `--leave-call`) for a compositor's key bindings; global on Windows while a
  call is on.

### Audio

- Screen share audio, in stereo and without voice processing.
- Linux: share what plays into any PipeWire / PulseAudio output. The share dialog lists the
  outputs and the applications playing into each; several sources can be mixed and adjusted
  while sharing.
- Windows: system audio with the screen share, without the call's own sound.
- Volume per participant and per screen share, 0 to 200 %, remembered; "Mute for me".
- Calls never change the system's microphone volume.

### Layout and windows

- Fullscreen for every tile.
- Pop-out: any tile in its own window.
- Equal grid layout: every tile the same size, screen shares included.

### App

- Own name, icon, profile directory (`~/.config/InterCom`) and URL scheme; installs next to
  Element without sharing data with it.
- Flat dark and light themes.
- Hardware video decoding on Linux (VA-API) enabled by default.
- Call diagnostics: an overlay with live statistics for every track (Ctrl+Alt+D), a JSON-lines
  log per run, and `tools/diag-summary.py` to turn logs into verdicts.
- Windows x64 installer, cross-built from Linux (not code signed).

### Known limitations

- No hardware video encoding on Linux with NVIDIA GPUs (Chromium has no NVENC backend there).
- No macOS build.
- No automatic updates.
