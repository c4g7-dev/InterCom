# Changelog

Versions are `<Element Web version>-intercom.<n>`: the upstream release InterCom is based on,
followed by the InterCom revision.

## Android 26.11.1-intercom.3

`android-v26.11.1-intercom.3`, based on Element X Android 26.11.1. The call library is
`0.1.2-intercom.2`, and the RTC core under it is now InterCom's own build as well: the fork
[intercom-matrix-rust-rtc](https://github.com/c4g7-dev/intercom-matrix-rust-rtc) of
matrix-rust-rtc 0.5.0 (`0.5.0-intercom.1`), a new submodule.

- **Phone audio in a screen share at music quality.** What the phone plays is now sent as stereo
  Opus at 160 kbit/s, every frame of it; 128 and 192 kbit/s can be chosen under "Audio quality"
  in the share sheet. Before, it went out with the settings of a voice: 48 kbit/s in one
  channel, with silence left out, which cut quiet passages. The microphone is sent as before.
- **A shared screen's audio is played.** When somebody else shares a screen with audio, the phone
  now plays it, in stereo where it was sent so, with the voices and through the same output:
  earpiece, speaker or headset, with the call's volume keys.
- **A volume for every tile.** Press and hold somebody's tile: a slider from 0 to 200 % and
  "Mute for me", for that person's voice, and separately for the audio of the screen they share
  when you hold the share's tile. Only your phone hears the difference. It is remembered per
  person and per kind for later calls. The slider is the desktop's: half way is about half as
  loud, and 100 to 200 % is 0 to +12 dB, held back by a limiter where it would distort.
- arm64-v8a only, now by construction: the RTC core is built for that one ABI, and the build
  makes no other APK.
- What the self-built core changes for every call, compared with matrix-rust-rtc 0.5.0: nothing in
  what is sent unless a track asks for it (only the share's audio does); on the receiving side,
  a track that the media server offers as stereo is now answered and decoded as stereo, and a
  screen share's audio is handed to the app in two channels. The library exports the same
  symbols as 0.5.0 plus one record's metadata.
- Known limitations: a shared screen's audio is played as part of the call, so over a Bluetooth
  headset it is in the headset's call mode, mono and narrow. Stereo and the bitrate of the
  phone's audio depend on the media server (a LiveKit SFU) granting what the track asks for,
  which a current one does.
- **Not tested on a device or in a call before release.** It builds, and the unit tests cover
  what the encoder is asked for on both sides of the Rust boundary, the SDP change, the volume
  curve, the limiter and the screens' logic. Whether a call sounds as intended is for the first
  call to show. Android does not install an older version over a newer one: going back to
  `android-v26.11.1-intercom.2` means uninstalling this one first, which signs the app out.

## 1.12.35-intercom.5

Uploads no longer crawl over HTTP/3, InterCom updates itself, and the room list has voice
channels with the people in them and a panel for your call.

### Uploads

- **HTTP/3 is off by default.** Uploading several pictures failed with "Upload Failed" on a
  homeserver behind Traefik, which offers HTTP/3, in a GRE tunnel. Measured there: an upload over
  HTTP/3 (QUIC) ran at about 10 KB/s until it timed out; the same upload over HTTP/2 ran at 0.7 to
  3.7 MB/s. Chromium keeps using HTTP/3 once a server has offered it and does not fall back when it
  is slow, so InterCom now starts with `--disable-quic`. `--enable-quic` or
  `INTERCOM_ENABLE_QUIC=1` turns it back on. Nothing else changes: downloads, sync and calls
  (which are WebRTC, not HTTP) were not affected.
- An upload that fails without an answer from the server, or with a 5xx, 408 or 429, is tried once
  more after 1.5 s before "Upload Failed" is shown. What the server refused (too large, not
  allowed) and what you cancelled is not tried again.
- **Galleries: two cases in which pictures sent together were not grouped.** With the developer
  option "Show hidden events in timeline" on, no gallery was formed at all; that is fixed. And pictures whose uploads ended more than two minutes apart, as they did on the slow
  connection above, were shown one by one: pictures confirmed together in the batch dialog are
  now marked as one batch (`io.intercom.gallery` in the event, ignored by other clients) and
  grouped however long they took. Pictures sent before this release are grouped by time as
  before. In an encrypted room a batch was, and is, grouped while sending, once sent and after a
  restart; that is now covered by tests.

### Updates

- **InterCom updates itself** from the releases of this repository. It looks 30 seconds after it
  starts and every six hours, downloads the new version, checks it against the release's
  `SHA256SUMS` and then shows "InterCom <version> is available" with a "Restart to update" button
  and a link to the release notes. Nothing is installed before you click. Settings → InterCom has
  the switch for the automatic check, "Check now" and what the updater is doing.
- Linux: the downloaded archive is unpacked beside the install directory, and on restart the two
  are swapped; the previous version stays beside it as `<directory>.old`. InterCom then starts
  again with the options it was started with. The directory and the one above it must be writable;
  where they are not, the toast leads to the release page instead.
- If you start InterCom through a script of your own, let it export `INTERCOM_LAUNCHER` (its own
  path) so that the update starts the script again rather than the program behind it; see
  "Updates" in `element-web/apps/desktop/intercom/README`. `run-intercom.sh` does.
- Windows: the installer is downloaded and checked, and run silently on restart; it starts
  InterCom again.
- **1.12.35-intercom.4 and older do not know about updates**: install this version by hand once.
- The builds are not code signed. The checksum catches a broken download; it comes from the same
  release as the file, so it is no proof of who made it.
- `--no-update` turns the updater off. A build that is not a release never updates.

### Voice channels

- Rooms that are their call (video rooms and call rooms) are **voice channels**: they have a
  "Voice channels" section in the room list, after the "Text channels" (which used to be
  "Rooms"), and a speaker in place of the avatar. Favourites, People, low priority and your own
  sections are as they were, and a voice channel you move into one of those stays there.
- **Who is in the call is listed under the channel**, whether or not you are in it yourself. Once
  you are in it the list also shows who is talking (a ring around the avatar), whose microphone
  is off, who is sharing a screen ("LIVE") and whether you are deafened. Other people's
  deafening is not known to the call and not shown.
- **One click joins**: clicking a voice channel, or somebody in its list, opens it and joins
  without the lobby.
- **A panel under the room list**: your avatar, name and presence, and buttons for the
  microphone, deafen and the settings. While you are in a call, a strip above it says "Voice
  connected" (or "Reconnecting…") with the room, which is a button back to the call, and has the
  camera, screen share and leave buttons. They do what Ctrl+Shift+M, Ctrl+Shift+D and
  Ctrl+Shift+V do; starting a screen share shows the call first, where the screen is chosen. The
  bars beside "Voice connected" show connected or reconnecting, not a measured signal quality.
- The room list no longer folds away when you join a call.

### Look

- InterCom Dark has three layers: the space bar darkest, the room list between, the timeline
  lightest. Corners are 8 px. The search bar of the room list and the room header are 52 px
  high and line up. Messages of one sender sit closer together, and a new sender starts 12 px
  further down instead of 18. InterCom Light keeps its colours and gets the same layout.

### Diagnostics

- The `app_start` record says whether HTTP/3 was on (`quic`) and which InterCom release is running
  (`intercomVersion`).
- A failed upload writes an `upload_failed` record: the try, the HTTP status, the kind of error,
  the protocol the request went over (h2, h3, http/1.1) and whether it is tried again. Never a
  file name or a URL.
- The updater writes `updater` records for every step: the check, what was found, the download
  and its checksum, the swap or the installer, and errors.

### Builds

- Built like 1.12.35-intercom.4: on a Linux machine, the Windows installer cross-built with
  wine. It is not code signed.
- Not tested before release: an update from start to finish (there is no newer release to
  update to yet; the version comparison, the choice of release, the checksum and the directory
  swap are covered by tests with made-up releases and temporary directories), the Windows
  installer run by the updater, and everything above in a real call or against a real
  homeserver. The room list, the panel and both themes were looked at in the built web app with
  made-up data, with the call's messages to the app played by hand.

## 1.12.35-intercom.4

A call can share the room with its chat, pictures sent together are one gallery, and sending a
picture no longer waits on its preview.

### Calls

- **Call over the chat.** The call of a room is now shown above the room's timeline and
  composer, with a bar between them: drag it (or focus it and use the arrow keys, Home and End)
  to give the call more or less of the room. The height is remembered. The chevron on the bar
  folds the call away and brings it back (also: double click the bar, or Enter on it); the call
  goes on playing either way. The button beside it, and the one in the room header, give the
  call the whole room as before ("Call only"), and the header button brings the chat back. The
  choice is remembered; pop-out and picture-in-picture are as they were.
- **Click a tile to focus it.** One click on a tile shows it large with everybody in a strip
  beside it; a click on it again, or Escape, returns to the layout that was chosen. Other
  screen shares stay a page away in the large tile. A double click is still fullscreen, which
  is why a single click takes a fifth of a second to act.
- Diagnostics overlay: a screen share whose sound you muted for yourself (or turned to 0 %, or
  while deafened) now reads "receiving … · muted by you" in grey instead of a red "no sound".
  A browser measures no level for audio it does not play, so the check judges such a share by
  what arrives. `tools/diag-summary.py` leaves those readings out as well.

### Messages

- **Galleries.** Pictures sent one after the other by the same person, within two minutes of
  each other and with nothing between them, are shown as one grid of cropped previews, three
  to a row, with "+N" on the last one when there are more than nine. A click opens the picture;
  the lightbox then has previous and next buttons (and the arrow keys) for the whole gallery,
  and shows "2 of 5". Every picture is still an ordinary image message, so other clients show
  them as before, and reactions, replies and the menu of a single picture are reached from the
  lightbox. A picture you are linked to keeps a tile of its own.
- **Several pictures are sent as one batch.** Choosing, dropping or pasting more than one
  picture asks once, shows them as the gallery they will be, and takes an optional caption,
  which is sent with the first.
- **Sending a picture is faster.** What happened before the upload of a 12 megapixel JPEG,
  measured in the app's browser engine: about 100 ms to decode it, 475 ms to compute its
  blurhash from the 800 × 600 thumbnail, then the thumbnail's upload, and only then the
  picture's own. Now the picture's upload starts at once and the thumbnail is made beside it;
  the blurhash is computed from a 64 pixel copy (3 ms); the picture is decoded off the main
  thread; a PNG is no longer read whole and checksummed to find out whether it is a hi-dpi
  screenshot; and a JPEG is no longer read to find out whether it is animated. A video or
  audio file is no longer turned into a base64 copy in memory to read its length and first
  frame. The events are what they were: `m.image` with `info`, thumbnail and blurhash.
- A file that needs none of this (a .zip) was and is sent as it is. On a homeserver that makes
  its thumbnails while it answers the upload (Synapse, for unencrypted pictures) that part of
  the wait is the server's and stays.

### Diagnostics

- Every upload writes `upload_phase` records to the diagnostics log: how long decoding, the
  thumbnail, the blurhash, reading, encrypting, each request and the event took, with the
  file's size and type (never its name), and a closing record with the total.
  `tools/diag-summary.py` lists them under "Uploads".

### Builds

- The web app no longer contains the paths of the machine it was built on.
- Built like 1.12.35-intercom.3: on a Linux machine, the Windows installer cross-built with
  wine. It is not code signed.
- Not tested in a real call or against a real homeserver before release: the gallery, the
  lightbox, the batch dialog and the call over the chat were looked at in the built app with
  made-up data; focusing a tile and the overlay change are covered by unit tests only.

## 1.12.35-intercom.3

The volume above 100 % is now clearly louder, and the diagnostics overlay judges share audio
per member.

### Calls

- **Volume above 100 % that is heard.** 200 % used to be twice the amplitude (+6 dB) with
  nothing to stop the peaks from clipping, which was barely louder. The second half of the
  slider is now 0 to +12 dB in even steps (150 % is +6 dB, 200 % is +12 dB, four times the
  amplitude), played through a limiter so that loud passages are held back instead of
  distorting. The same for a member's voice and for a screen share's audio, in the tile, in
  the menus, in fullscreen and in the pop-out window.
- The sliders show the gain beside the percentage above 100 %, e.g. "180% · +9.6 dB".
- Below 100 % the slider is in steps the ear takes as even as well: half way is about half as
  loud (−12 dB) rather than −6 dB. **A volume set below 100 % before this release is therefore
  quieter than it was**; move the slider up a little where that matters.
- Dragging the slider no longer rebuilds the audio path for every step, and boosted audio
  follows the output device chosen in the call when it changes.

### Diagnostics

- A volume change is written to the diagnostics log with its gain in dB and whether the limiter
  is in the path.
- Overlay: "Share audio flowing" is now "My share audio sending" (the own share's bitrate and
  level) and "Share audio received from <name>" for each member who is sharing a screen with
  audio. A member who is not sharing no longer turns it red while your own share is fine.
  "Receiving top layer" is per member too and is not shown where nobody shares. In the log the
  checks are `share_audio_send`, `share_audio_recv:<member>` and `top_layer:<member>`;
  `tools/diag-summary.py` reads both the new and the old form.

### Builds

- Built like 1.12.35-intercom.2: on a Linux machine, the Windows installer cross-built with
  wine. It is not code signed.

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
