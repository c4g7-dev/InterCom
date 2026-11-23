#!/usr/bin/env python3
# Copyright 2026 InterCom contributors
#
# SPDX-License-Identifier: AGPL-3.0-only
"""Verdicts per feature from InterCom diagnostics logs.

    diag-summary.py ~/.config/InterCom/logs/diag-*.jsonl [more files, one per participant]

Reads the JSON-lines files the desktop app writes (one record per line, see
element-web/apps/desktop/src/intercom-diagnostics.ts and
element-call/src/diagnostics/) and prints, per file and per call: whether the
microphone was publishing with audio after the join, how the screen share was
sent and received, whether its audio flowed, the pop-out and fullscreen events,
network outliers and errors. Given the files of several participants, what one
sent is set against what the others received (tracks are matched by their id).

Python 3 standard library only. Exit code 0 unless a file cannot be read.
"""

import argparse
import json
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime

PASS, FAIL, WARN, INFO = "PASS", "FAIL", "WARN", "INFO"


def load(path):
    records, bad = [], 0
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                bad += 1
                continue
            if isinstance(record, dict) and "type" in record:
                if "t" not in record:
                    record["t"] = wall_ms(record.get("wall"))
                records.append(record)
    return records, bad


def wall_ms(wall):
    try:
        return int(datetime.fromisoformat(wall.replace("Z", "+00:00")).timestamp() * 1000)
    except (AttributeError, ValueError):
        return 0


def clock(ms):
    return datetime.fromtimestamp(ms / 1000).strftime("%H:%M:%S") if ms else "--:--:--"


def secs(ms):
    return f"{ms / 1000:.1f} s"


def mbps(bits):
    if bits is None:
        return "?"
    return f"{bits / 1e6:.2f} Mbps" if bits >= 1e6 else f"{bits / 1e3:.0f} kbps"


def values(records, key):
    return [r[key] for r in records if isinstance(r.get(key), (int, float))]


def spread(numbers, unit="", digits=0):
    """min / median / max of a series, or '?'."""
    if not numbers:
        return "?"
    fmt = f"{{:.{digits}f}}"
    return "/".join(fmt.format(n) for n in (min(numbers), statistics.median(numbers), max(numbers))) + unit


def percentile(numbers, fraction):
    if not numbers:
        return None
    ordered = sorted(numbers)
    return ordered[min(len(ordered) - 1, int(len(ordered) * fraction))]


def histogram(items):
    counts = Counter(items)
    total = sum(counts.values()) or 1
    return ", ".join(f"{name} {count * 100 // total}%" for name, count in counts.most_common())


def hw_name(record):
    hw = record.get("hw")
    return "HW" if hw is True else "SW" if hw is False else "?"


class Call:
    """The records of one call of one participant: from call_start to call_end."""

    def __init__(self, source, start):
        self.source = source
        self.start = start
        self.participant = start.get("participant", "?")
        self.records = [start]

    @property
    def t0(self):
        return self.start["t"]

    @property
    def t1(self):
        return self.records[-1]["t"]

    def of(self, *types):
        return [r for r in self.records if r["type"] in types]

    def tracks(self, direction=None, source=None):
        return [
            r
            for r in self.records
            if r["type"] == "track"
            and (direction is None or r.get("dir") == direction)
            and (source is None or r.get("source") == source)
        ]


def split_calls(path, records):
    calls, current = [], None
    for record in records:
        if record["type"] == "call_start":
            current = Call(path, record)
            calls.append(current)
        elif current is not None:
            current.records.append(record)
            if record["type"] == "call_end":
                current = None
    return calls


class Report:
    def __init__(self):
        self.lines = []
        self.verdicts = []

    def head(self, text):
        self.lines.append("")
        self.lines.append(text)
        self.lines.append("=" * len(text))

    def section(self, text):
        self.lines.append("")
        self.lines.append(f"-- {text}")

    def verdict(self, status, feature, text):
        self.verdicts.append({"status": status, "feature": feature, "detail": text})
        self.lines.append(f"  [{status}] {feature}: {text}")

    def note(self, text):
        self.lines.append(f"         {text}")


def report_environment(report, records):
    starts = [r for r in records if r["type"] == "app_start"]
    if not starts:
        report.note("no app_start record (not a desktop log, or the file was cut)")
        return
    start = starts[-1]
    osinfo = (start.get("os") or {})
    session = start.get("sessionType") or ("wayland" if start.get("waylandDisplay") else "?")
    report.note(
        f"{start.get('app')} {start.get('version')}, Electron {start.get('electron')} / Chromium {start.get('chromium')}, "
        f"{osinfo.get('platform')} {osinfo.get('release')} ({session}, {start.get('desktop')})"
    )
    switches = (start.get("featureSwitches") or {})
    report.note(f"enable-features: {switches.get('enable-features', '-')}")
    report.note(f"disable-features: {switches.get('disable-features', '-')}")
    gpu = [r for r in records if r["type"] == "gpu"]
    status = (gpu[-1] if gpu else start).get("gpuFeatureStatus") or {}
    wanted = ("video_decode", "video_encode", "gpu_compositing", "webgl", "vulkan")
    report.note("GPU: " + ", ".join(f"{k}={status.get(k, '?')}" for k in wanted))
    info = [r for r in records if r["type"] == "gpu_info"]
    if info:
        summary = (info[-1].get("info") or {})
        report.note(f"GL renderer: {summary.get('glRenderer', '?')}")


def report_join(report, call, args):
    report.section("Mute on join / microphone")
    initial = next((r for r in call.of("mute") if r.get("source") == "microphone" and r.get("reason") == "initial"), None)
    states = call.of("participation")
    connected = next((r for r in states if r.get("state") == "connected"), None)
    if connected:
        report.note(f"connected {secs(connected['t'] - call.t0)} after the call view started")
    else:
        report.note("never reached 'connected': " + " -> ".join(r.get("state", "?") for r in states))
    for record in call.of("devices"):
        report.note(f"devices {record.get('kind')}: {record.get('count')} {record.get('labels')}")
    if initial is not None:
        report.note(f"microphone switch at the join: {'on' if initial.get('enabled') else 'off'}")

    mic = call.tracks("send", "microphone")
    sounding = [r for r in mic if not r.get("muted") and (r.get("audioEnergyDelta") or 0) > args.audio_threshold]
    sending = [r for r in mic if not r.get("muted") and (r.get("bitrate") or 0) > 0]
    wanted_on = initial is None or initial.get("enabled")

    # Whatever turned the microphone off without the user asking
    unasked = [
        r
        for r in call.of("mute")
        if r.get("source") == "microphone"
        and r.get("enabled") is False
        and r.get("reason") in ("handler_refused", "device_lost", "publish_failure", "device_refused", "no_device")
    ]
    unasked += [r for r in call.of("mute_request") if r.get("reason") in ("auto_large_call", "host")]
    attempts = [r for r in call.of("publish_attempt") if r.get("source") == "microphone"]
    failures = [r for r in call.of("publish_result") if r.get("source") == "microphone" and not r.get("ok")]

    if not wanted_on:
        report.verdict(INFO, "mute-on-join", "joined with the microphone switched off (by the initial state, not by a failure)")
    elif sounding:
        delay = sounding[0]["t"] - call.t0
        status = PASS if delay <= args.join_threshold * 1000 and not unasked else WARN if not unasked else FAIL
        report.verdict(
            status,
            "mute-on-join",
            f"microphone publishing with audio {secs(delay)} after the join "
            f"(threshold {args.join_threshold:.0f} s), {len(unasked)} unasked mute(s)",
        )
    elif sending:
        report.verdict(
            WARN,
            "mute-on-join",
            f"microphone sent data from {secs(sending[0]['t'] - call.t0)} but no sound was ever measured "
            "(silent room, muted hardware, or the wrong device)",
        )
    else:
        report.verdict(FAIL, "mute-on-join", "the microphone never published although its switch was on")

    for record in unasked:
        report.note(
            f"{clock(record['t'])} +{secs(record['t'] - call.t0)} unasked mute: {record.get('reason')}"
            + (f" (asked {record.get('asked')})" if "asked" in record else "")
        )
    if attempts:
        report.note(f"publish attempts: {len(attempts)}, failed: {len(failures)}")
    for record in failures:
        error = (record.get("error") or {})
        report.note(
            f"{clock(record['t'])} attempt {record.get('attempt')} {record.get('outcome')}: "
            f"{error.get('name')}: {error.get('message')}"
        )
    user = [r for r in call.of("mute") if r.get("source") == "microphone" and r.get("reason") == "user"]
    if user:
        report.note("user toggles: " + ", ".join(f"{clock(r['t'])} {'on' if r.get('enabled') else 'off'}" for r in user))
    ticks = [r for r in call.of("tick") if r.get("micEnabled")]
    failing = [r for r in ticks if ((r.get("checks") or {}).get("mic_audio") or {}).get("status") == "fail"]
    if ticks:
        reasons = histogram(r["checks"]["mic_audio"].get("detail", "?").split(" for ")[0] for r in failing)
        report.note(
            f"'Mic publishing with audio' failed in {len(failing)}/{len(ticks)} readings with the switch on"
            + (f": {reasons}" if failing else "")
        )
    if mic:
        report.note(
            f"mic bitrate min/med/max {spread(values(mic, 'bitrate'), ' bps')}, "
            f"level max {max(values(mic, 'audioLevel') or [0]):.3f}, codec {mic[-1].get('codec')}"
        )


def describe_video(report, records, label):
    sizes = [f"{r.get('width')}x{r.get('height')}" for r in records if r.get("width")]
    report.note(f"{label}: {len(records)} readings over {secs(records[-1]['t'] - records[0]['t'])}")
    report.note(f"  resolution: {histogram(sizes) or 'no frames'}")
    report.note(
        f"  fps min/med/max {spread(values(records, 'fps'))}, bitrate {spread([v / 1e6 for v in values(records, 'bitrate')], ' Mbps', 2)}"
        + (f", target {spread([v / 1e6 for v in values(records, 'targetBitrate')], ' Mbps', 2)}" if values(records, "targetBitrate") else "")
    )
    coders = histogram(f"{r.get('codec', '?')} {r.get('impl', '?')} [{hw_name(r)}]" for r in records)
    report.note(f"  coder: {coders}")


def report_share_sent(report, call, args):
    report.section("Screen share (sent)")
    starts = call.of("screen_share_start")
    sent = call.tracks("send", "screen_share")
    for start in starts:
        capture = (start.get("capture") or {})
        report.note(
            f"{clock(start['t'])} started: preset {start.get('preset')}, resolution {start.get('resolution')}, "
            f"codec {start.get('codec')} -> {capture.get('codec')}, audio {start.get('audio')}, hint {capture.get('contentHint')}, "
            f"degradation {capture.get('degradationPreference')}, simulcast {capture.get('simulcast')}"
        )
    for error in call.of("screen_share_error"):
        detail = (error.get("error") or {})
        report.note(
            f"{clock(error['t'])} {error.get('phase')} failed"
            + (" (picker cancelled)" if error.get("cancelled") else f": {detail.get('name')}: {detail.get('message')}")
        )
    if not sent:
        report.verdict(INFO if not starts else FAIL, "screen-share", "no screen share was sent" + (" although one was started" if starts else ""))
        return
    by_sid = defaultdict(list)
    for record in sent:
        by_sid[record["sid"]].append(record)
    for sid, records in by_sid.items():
        describe_video(report, records, f"share {sid}")
        limits = [r.get("limitation", "?") for r in records]
        report.note(f"  limitation: {histogram(limits)}; durations at the end {records[-1].get('limitationDurations')}")
        capture = (records[-1].get("capture") or {})
        encodings = records[-1].get("encodings")
        report.note(
            f"  captured {capture.get('width')}x{capture.get('height')}@{capture.get('fps')}, contentHint {histogram(r.get('contentHint', '?') for r in records)}, "
            f"degradation {records[-1].get('degradationPreference')}, scalability {records[-1].get('scalabilityMode')}"
        )
        report.note(f"  sender encodings: {encodings}")
        ticks = [r for r in call.of("tick") if records[0]["t"] <= r["t"] <= records[-1]["t"] + 2500]
        res_fail = [r for r in ticks if ((r.get("checks") or {}).get("share_resolution") or {}).get("status") == "fail"]
        # The first readings are the encoder ramping up
        settled = [r for r in records[args.warmup:] if r.get("width")]
        limited = [r for r in settled if r.get("limitation") not in (None, "none")]
        expected = next((r["share"].get("expected") for r in reversed(ticks) if (r.get("share") or {}).get("expected")), None)
        share_ok = len(res_fail) <= max(args.warmup, len(ticks) * 0.05)
        limited_share = len(limited) / len(settled) if settled else 0
        status = PASS if share_ok and limited_share <= 0.1 else WARN if share_ok else FAIL
        report.verdict(
            status,
            "screen-share",
            f"{sid}: expected {expected and '%dx%d' % (expected['width'], expected['height'])}, "
            f"resolution check failed in {len(res_fail)}/{len(ticks)} readings, "
            f"quality limited in {limited_share * 100:.0f}% of readings after warm-up",
        )
        if res_fail:
            report.note(f"  resolution failures: {histogram(r['checks']['share_resolution'].get('detail') for r in res_fail)}")
    budgets = call.of("budget")
    if budgets:
        report.note("egress budget recalculations:")
        for record in budgets[-args.max_events:]:
            report.note(
                f"  {clock(record['t'])} {record.get('viewers')} viewer(s) of {record.get('mbps')} Mbps -> "
                f"cap {mbps(record.get('maxBitrate'))} @ {record.get('maxFramerate')} fps (uncapped {mbps(record.get('uncappedBitrate'))})"
            )


def report_received(report, call, senders, args):
    report.section("Received video")
    received = [r for r in call.tracks("recv") if r.get("kind") == "video"]
    if not received:
        report.note("no video received")
        return
    by_sid = defaultdict(list)
    for record in received:
        by_sid[record["sid"]].append(record)
    for sid, records in by_sid.items():
        last = records[-1]
        describe_video(report, records, f"{last.get('source')} from {last.get('participant')} ({sid})")
        report.note(
            f"  freezes {last.get('freezeCount', 0)} ({last.get('freezeDurationS', 0)} s), frames dropped {last.get('framesDropped', 0)}, "
            f"NACK/PLI/FIR {last.get('nack', 0)}/{last.get('pli', 0)}/{last.get('fir', 0)}, published {last.get('published')}"
        )
        if last.get("source") != "screen_share":
            continue
        ticks = [r for r in call.of("tick") if records[0]["t"] <= r["t"] <= records[-1]["t"] + 2500]
        # One verdict per sharing member since 1.12.35-intercom.3, one for all before
        low = [
            r
            for r in ticks
            if (
                (r.get("checks") or {}).get(f"top_layer:{last.get('participant')}")
                or (r.get("checks") or {}).get("top_layer")
                or {}
            ).get("status")
            == "fail"
        ]
        status = PASS if len(low) <= max(args.warmup, len(ticks) * 0.05) else FAIL
        report.verdict(status, "received-share", f"{sid}: below the top layer in {len(low)}/{len(ticks)} readings")
        sender = senders.get(sid)
        if sender:
            sent_sizes = Counter(f"{r.get('width')}x{r.get('height')}" for r in sender if r.get("width"))
            got_sizes = Counter(f"{r.get('width')}x{r.get('height')}" for r in records if r.get("width"))
            sent_top = sent_sizes.most_common(1)[0][0] if sent_sizes else "?"
            got_top = got_sizes.most_common(1)[0][0] if got_sizes else "?"
            report.verdict(
                PASS if sent_top == got_top else FAIL,
                "share-end-to-end",
                f"{sid}: sender sent mostly {sent_top}, this viewer received mostly {got_top}",
            )
        else:
            report.note("  (no log of the sender given: pass its file too to compare sent and received)")


def report_share_audio(report, call, args):
    report.section("Share audio")
    audio = call.tracks(source="screen_share_audio")
    asked = [r for r in call.of("screen_share_start") if r.get("audio") not in (None, "none")]
    if not audio:
        if asked and call.tracks("send", "screen_share"):
            report.verdict(FAIL, "share-audio", f"a share was started with audio '{asked[-1].get('audio')}' but no audio track was published")
        else:
            report.verdict(INFO, "share-audio", "no screen share audio in this call")
        return
    by_sid = defaultdict(list)
    for record in audio:
        by_sid[(record["dir"], record["sid"])].append(record)
    for (direction, sid), records in by_sid.items():
        measured = [r for r in records if "audioEnergyDelta" in r]
        # A share the viewer muted for themselves is not played, and the browser measures no
        # level for audio it does not play: those readings say nothing about the share
        muted_here = [r for r in measured if direction == "recv" and r.get("playbackVolume") == 0]
        if muted_here:
            measured = [r for r in measured if r.get("playbackVolume") != 0]
            if not measured:
                report.verdict(
                    INFO,
                    "share-audio",
                    f"{direction} {sid} ({records[-1].get('participant')}): muted by the viewer in all {len(muted_here)} readings, "
                    f"bitrate med {mbps(statistics.median(values(records, 'bitrate') or [0]))}",
                )
                continue
        flowing = [r for r in measured if r["audioEnergyDelta"] > args.audio_threshold and not r.get("muted")]
        share = len(flowing) / len(measured) if measured else 0
        status = PASS if share >= 0.5 else WARN if flowing else FAIL
        report.verdict(
            status,
            "share-audio",
            f"{direction} {sid} ({records[-1].get('participant')}): sound in {share * 100:.0f}% of {len(measured)} readings, "
            f"level max {max(values(records, 'audioLevel') or [0]):.3f}, bitrate med {mbps(statistics.median(values(records, 'bitrate') or [0]))}, "
            f"codec {records[-1].get('codec')}"
            + (f", concealed max {max(values(records, 'concealedPct') or [0])}%" if direction == "recv" else "")
            + (f", muted by the viewer in {len(muted_here)} more" if muted_here else ""),
        )


def report_windows(report, call, args):
    report.section("Pop-out / fullscreen / volume")
    events = call.of("popout", "fullscreen", "test_pattern", "snapshot", "volume")
    if not events:
        report.note("none")
        return
    counts = Counter(
        f"{r['type']} {r.get('action') or ('on' if r.get('on') else 'off' if 'on' in r else '')}".strip() for r in events
    )
    report.note(", ".join(f"{name} x{count}" for name, count in counts.items()))
    for record in events[-args.max_events:]:
        fields = {k: v for k, v in record.items() if k not in ("v", "t", "seq", "type", "wall", "window")}
        report.note(f"{clock(record['t'])} {record['type']} {fields}")
    blocked = [r for r in events if r.get("action") == "blocked"]
    opened = [r for r in events if r["type"] == "popout" and r.get("action") == "open"]
    if blocked:
        report.verdict(FAIL, "pop-out", f"{len(blocked)} window(s) were blocked by the host")
    elif opened:
        report.verdict(PASS, "pop-out", f"{len(opened)} pop-out(s) opened")


def report_network(report, call, args):
    report.section("Network")
    tracks = call.tracks()
    if not tracks:
        report.note("no track readings")
        return
    loss = values(tracks, "lossPct")
    rtt = values(tracks, "rttMs")
    report.note(
        f"loss % p50/p95/max: {percentile(loss, 0.5)}/{percentile(loss, 0.95)}/{max(loss) if loss else None}; "
        f"RTT ms p50/p95/max: {percentile(rtt, 0.5)}/{percentile(rtt, 0.95)}/{max(rtt) if rtt else None}"
    )
    lossy = [r for r in tracks if (r.get("lossPct") or 0) > args.loss_threshold]
    slow = [r for r in tracks if (r.get("rttMs") or 0) > args.rtt_threshold]
    status = PASS if len(lossy) <= len(tracks) * 0.02 and len(slow) <= len(tracks) * 0.02 else WARN
    report.verdict(
        status,
        "network",
        f"{len(lossy)} reading(s) above {args.loss_threshold}% loss, {len(slow)} above {args.rtt_threshold} ms RTT, of {len(tracks)}",
    )
    for record in sorted(lossy, key=lambda r: -r["lossPct"])[: args.max_events]:
        report.note(f"{clock(record['t'])} {record['dir']} {record['source']} {record['participant']}: loss {record['lossPct']}%")
    reconnects = [r for r in call.of("participation") if r.get("state") in ("reconnecting", "failed")]
    for record in reconnects:
        report.note(f"{clock(record['t'])} participation {record.get('state')} {record.get('reason', '')} {record.get('error', '')}")
    if reconnects:
        report.verdict(WARN, "connection", f"{len(reconnects)} reconnect/failure event(s)")


def report_uploads(report, records, args):
    """Where the time of each file sent went: the `upload_phase` records of the web app."""
    phases = [r for r in records if r["type"] == "upload_phase"]
    totals = [r for r in phases if r.get("phase") == "total"]
    failures = [r for r in records if r["type"] == "upload_failed"]
    if not totals and not failures:
        return
    report.section("Uploads")
    # A request that failed: what the server said (or that it said nothing) and over which protocol
    for failure in failures[-args.max_events :]:
        status = failure.get("status")
        report.note(
            f"{clock(failure['t'])} try {failure.get('attempt')} failed: "
            + (f"HTTP {status}" if status else "no answer")
            + f" ({failure.get('error')}), protocol {failure.get('protocol') or 'unknown'}, "
            + ("tried again" if failure.get("willRetry") else "given up")
        )
    if failures:
        over_h3 = sum(1 for r in failures if r.get("protocol") == "h3")
        report.verdict(
            WARN,
            "upload requests",
            f"{len(failures)} failed, {sum(1 for r in failures if not r.get('willRetry'))} given up"
            + (f"; {over_h3} over HTTP/3 (off by default since 1.12.35-intercom.5, see --enable-quic)" if over_h3 else ""),
        )
    if not totals:
        return
    for total in totals[-args.max_events :]:
        parts = total.get("phases") or {}
        slowest = sorted(parts.items(), key=lambda item: -item[1])[:4]
        size = total.get("bytes") or 0
        http = parts.get("http")
        rate = f", {size * 8 / http / 1000:.1f} Mbit/s in the request" if http and size else ""
        report.note(
            f"{clock(total['t'])} {total.get('mime')} {size / 1e6:.2f} MB {total.get('outcome')} in {total.get('ms', 0):.0f} ms{rate}: "
            + ", ".join(f"{name} {ms:.0f}" for name, ms in slowest)
        )
    sent = [r for r in totals if r.get("outcome") == "sent"]
    local = [
        sum(ms for name, ms in (r.get("phases") or {}).items() if not name.endswith("http") and name not in ("send_event", "wait_previous"))
        for r in sent
    ]
    slow = [ms for ms in local if ms > 1000]
    report.verdict(
        PASS if not slow else WARN,
        "uploads",
        f"{len(sent)}/{len(totals)} sent; time spent in the app before and beside the requests: {spread(local, ' ms')}"
        + (f"; over 1 s in {len(slow)}" if slow else ""),
    )


def report_galleries(report, records, args):
    """What became of pictures sent together: the `gallery_decision` records of the web app."""
    decisions = [r for r in records if r["type"] == "gallery_decision"]
    refreshes = [r for r in records if r["type"] == "upload_token_refresh"]
    if refreshes:
        report.section("Access token")
        for record in refreshes[-args.max_events :]:
            report.note(
                f"{clock(record['t'])} renewed for an upload ({record.get('reason')}): "
                + ("ok" if record.get("ok") else f"failed ({record.get('error') or record.get('outcome')})")
                + f" in {record.get('ms', 0):.0f} ms"
            )
        failed = sum(1 for r in refreshes if not r.get("ok"))
        report.verdict(PASS if not failed else WARN, "token renewal", f"{len(refreshes)} for uploads, {failed} failed")
    if not decisions:
        return
    report.section("Galleries")
    # The last record of a run is what the timeline ended up showing; runs are told apart by their first time
    parted = 0
    for record in decisions[-args.max_events :]:
        items = record.get("items") or []
        outcomes = [item.get("outcome") for item in items]
        why = [o for o in outcomes[1:] if o != "joined"]
        parted += bool(why)
        between = sorted({b for item in items for b in item.get("between") or [] if b.endswith(":tile")})
        report.note(
            f"{clock(record['t'])} {record.get('pictures')} pictures -> galleries {record.get('galleries')}"
            + f" (layout {record.get('layout')}, timeline {record.get('timeline')}, hidden shown {record.get('hiddenShown')},"
            + f" grouping {record.get('grouping')}): {' '.join(str(o) for o in outcomes)}"
            + (f"; tiles between: {', '.join(between)}" if between else "")
        )
    report.verdict(
        PASS if not parted else WARN,
        "galleries",
        f"{len(decisions)} decision(s) logged" + (f", {parted} of the last with pictures that did not join" if parted else ""),
    )


def report_errors(report, records, args):
    report.section("Errors")
    console = [r for r in records if r["type"] == "console"]
    errors = [r for r in console if r.get("level") == "error"]
    hard = [r for r in records if r["type"] in ("error", "render_process_gone", "child_process_gone", "diag_unparsed")]
    dropped = sum(r.get("count", 0) for r in records if r["type"] == "console_dropped")
    report.note(
        f"console: {len(errors)} error(s), {len(console) - len(errors)} warning(s)"
        + (f", {dropped} more dropped by the rate limit" if dropped else "")
    )
    for text, count in Counter(r.get("text", "")[:160] for r in errors).most_common(args.max_events):
        report.note(f"  x{count} {text}")
    for record in hard[: args.max_events]:
        fields = {k: v for k, v in record.items() if k not in ("v", "seq", "wall")}
        report.note(f"  {clock(record['t'])} {fields}")
    report.verdict(PASS if not hard else FAIL, "errors", f"{len(hard)} crash/diagnostics error record(s)")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="+", help="diag-*.jsonl, one or more per participant")
    parser.add_argument("--join-threshold", type=float, default=10.0, help="seconds from join to the microphone carrying sound (default 10)")
    parser.add_argument("--audio-threshold", type=float, default=1e-7, help="energy added per reading above which a track carries sound")
    parser.add_argument("--loss-threshold", type=float, default=2.0, help="packet loss %% counted as an outlier (default 2)")
    parser.add_argument("--rtt-threshold", type=float, default=150.0, help="round trip ms counted as an outlier (default 150)")
    parser.add_argument("--warmup", type=int, default=3, help="readings after a share starts that are not judged (default 3)")
    parser.add_argument("--max-events", type=int, default=12, help="how many events of a kind to list (default 12)")
    parser.add_argument("--json", action="store_true", help="print the verdicts as JSON instead of text")
    args = parser.parse_args()

    loaded = []
    for path in args.files:
        try:
            records, bad = load(path)
        except OSError as error:
            print(f"{path}: {error}", file=sys.stderr)
            return 2
        calls = split_calls(path, records)
        loaded.append((path, records, bad, calls))

    # What every participant sent, by track id, for the viewers' side of the comparison
    senders = defaultdict(list)
    for _path, _records, _bad, calls in loaded:
        for call in calls:
            for record in call.tracks("send"):
                if record.get("kind") == "video":
                    senders[record["sid"]].append(record)

    output = []
    for path, records, bad, calls in loaded:
        report = Report()
        report.head(f"{path}")
        report.note(f"{len(records)} records, {bad} unreadable line(s), {len(calls)} call(s)")
        report_environment(report, records)
        for index, call in enumerate(calls, 1):
            report.head(f"Call {index}: {call.participant}  {clock(call.t0)} - {clock(call.t1)} ({secs(call.t1 - call.t0)})")
            ticks = call.of("tick")
            if ticks:
                report.note(f"remote members min/max: {min(values(ticks, 'viewers') or [0])}/{max(values(ticks, 'viewers') or [0])}")
            report_join(report, call, args)
            report_share_sent(report, call, args)
            report_received(report, call, senders, args)
            report_share_audio(report, call, args)
            report_windows(report, call, args)
            report_network(report, call, args)
        report_uploads(report, records, args)
        report_galleries(report, records, args)
        report_errors(report, records, args)
        output.append({"file": path, "verdicts": report.verdicts, "text": report.lines})

    if args.json:
        json.dump([{"file": o["file"], "verdicts": o["verdicts"]} for o in output], sys.stdout, indent=2)
        print()
    else:
        for item in output:
            print("\n".join(item["text"]))
        print("\nVerdicts")
        print("========")
        for item in output:
            print(item["file"])
            for verdict in item["verdicts"]:
                print(f"  [{verdict['status']}] {verdict['feature']}: {verdict['detail']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
