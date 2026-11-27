#!/usr/bin/env bash
# Launches the locally built Lattice desktop app.
# Profile: ~/.config/InterCom (separate from Element's ~/.config/Element).
# Diagnostics: ~/.config/InterCom/logs/diag-*.jsonl, summarised by tools/diag-summary.py.
# Extra arguments are passed through, e.g. --no-hw-video, --profile <name>, --help.
set -euo pipefail
DESKTOP="$(dirname "$(readlink -f "$0")")/element-web/apps/desktop"
# A build made while the app was running lands beside dist/ rather than over the binary in use
# (INTERCOM_DIST_DIR=dist-next intercom/build.sh, then dist-next2); the newest of them is started.
BIN=""
for dir in dist dist-next dist-next2; do
    candidate="$DESKTOP/$dir/linux-unpacked/intercom"
    if [[ -x "$candidate" && ( -z "$BIN" || "$candidate" -nt "$BIN" ) ]]; then
        BIN="$candidate"
    fi
done
if [[ -z "$BIN" ]]; then
    echo "Lattice is not built yet: $DESKTOP/dist/linux-unpacked/intercom is missing." >&2
    echo "Build it with element-web/apps/desktop/intercom/build.sh" >&2
    exit 1
fi
# For the updater: after an update the app starts this script again, with these arguments,
# rather than its executable (see "Updates" in element-web/apps/desktop/intercom/README).
INTERCOM_LAUNCHER="$(readlink -f "$0")"
INTERCOM_LAUNCHER_ARGS="$(printf '%s\n' "$@")"
export INTERCOM_LAUNCHER INTERCOM_LAUNCHER_ARGS
exec "$BIN" --ozone-platform-hint=auto --password-store=basic "$@"
