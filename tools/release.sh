#!/usr/bin/env bash
# Builds and publishes an InterCom release.
#
#   tools/release.sh <version> [--skip-build] [--no-publish]
#
#   <version>      e.g. 1.12.35-intercom.1: the Element Web version InterCom is based on, then
#                  the InterCom revision. CHANGELOG.md must have a "## <version>" section.
#   --skip-build   reuse the builds already in element-web/apps/desktop/{dist-release,dist-win}
#   --no-publish   build and collect the assets in release/<version>/, then stop: no commit, no
#                  tag, no push, no GitHub release
#
# What it does:
#   1. builds Element Call (embedded), the web app, the Linux app and the Windows installer,
#      one heavy step at a time
#   2. collects InterCom-<version>-linux-x64.tar.gz, InterCom-Setup-<version>-x64.exe and
#      SHA256SUMS in release/<version>/
#   3. commits the submodule pointers, tags this repository v<version> and the two forks
#      intercom-v<version>, and pushes branches and tags
#   4. creates the GitHub release with the notes from CHANGELOG.md
#
# Needs: pnpm 12, node, wine (Windows installer), gh (logged in), sha256sum.
# The built application is never started.
#
# Environment:
#   INTERCOM_REPO      GitHub repository of the release (default: taken from the origin remote)
#   INTERCOM_WINEPREFIX  wine prefix for the Windows build
#                        (default: ~/.cache/electron-builder/intercom-wine-prefix, never ~/.wine)
#   WEBPACK_JOBS       caps the minifier's workers when memory is tight
set -euo pipefail

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

VERSION=""
SKIP_BUILD=0
PUBLISH=1
for arg in "$@"; do
    case "$arg" in
        -h | --help) usage; exit 0 ;;
        --skip-build) SKIP_BUILD=1 ;;
        --no-publish) PUBLISH=0 ;;
        -*) echo "Unknown option: $arg" >&2; exit 2 ;;
        *) VERSION="$arg" ;;
    esac
done
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-intercom\.[0-9]+$ ]]; then
    echo "Usage: tools/release.sh <version> [--skip-build] [--no-publish]   (e.g. 1.12.35-intercom.1)" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$ROOT"
TAG="v$VERSION"
FORK_TAG="intercom-v$VERSION"
DESKTOP="$ROOT/element-web/apps/desktop"
OUT="$ROOT/release/$VERSION"
FORKS=(element-web element-call)

step() { printf '\n==> %s\n' "$*"; }
die() { echo "release.sh: $*" >&2; exit 1; }

# The remote of a fork that the intercom branch is pushed to
fork_remote() {
    if git -C "$1" remote | grep -qx intercom; then echo intercom; else echo origin; fi
}

# The section of CHANGELOG.md for this version, without its heading
notes() {
    awk -v v="$VERSION" '
        /^## / { if (found) exit; if ($2 == v) { found = 1; next } }
        found { print }
    ' CHANGELOG.md | sed -e '/./,$!d'
}

step "Checks"
for tool in git node pnpm sha256sum; do
    command -v "$tool" >/dev/null || die "$tool is not on the PATH"
done
[[ -n "$(notes)" ]] || die "CHANGELOG.md has no section '## $VERSION'"
BASE="$(node -p "require('$DESKTOP/package.json').version")"
[[ "$VERSION" == "$BASE"-intercom.* ]] || die "version $VERSION does not match Element Web $BASE"
if ((PUBLISH)); then
    command -v gh >/dev/null || die "gh is not on the PATH"
    gh auth status >/dev/null 2>&1 || die "gh is not logged in"
    [[ "$(git symbolic-ref --short HEAD)" == "main" ]] || die "not on the main branch"
    [[ -z "$(git status --porcelain --untracked-files=no --ignore-submodules=all)" ]] ||
        die "this repository has uncommitted changes"
    for fork in "${FORKS[@]}"; do
        [[ "$(git -C "$fork" symbolic-ref --short HEAD)" == "intercom" ]] ||
            die "$fork is not on the intercom branch"
        [[ -z "$(git -C "$fork" status --porcelain)" ]] || die "$fork has uncommitted changes"
    done
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then die "tag $TAG exists already"; fi
    REPO="${INTERCOM_REPO:-$(git remote get-url origin | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')}"
    [[ "$REPO" == */* ]] || die "cannot tell the GitHub repository; set INTERCOM_REPO=owner/name"
fi

export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=6144}"

if ((!SKIP_BUILD)); then
    command -v wine >/dev/null || die "wine is not on the PATH (needed for the Windows installer)"

    step "Element Call (embedded)"
    (cd element-call && scripts/build-intercom-embedded.sh)

    step "Web app and Linux app"
    # dist-release, so that a copy running from dist/ or dist-next/ is left alone
    rm -rf "$DESKTOP/dist-release"
    INTERCOM_DIST_DIR=dist-release "$DESKTOP/intercom/build.sh"

    step "Windows installer"
    rm -rf "$DESKTOP/dist-win"
    env -u DISPLAY -u WAYLAND_DISPLAY \
        WINEPREFIX="${INTERCOM_WINEPREFIX:-$HOME/.cache/electron-builder/intercom-wine-prefix}" \
        INTERCOM_TARGET=win INTERCOM_DIST_DIR=dist-win \
        "$DESKTOP/intercom/build.sh" --skip-web
fi

step "Assets"
LINUX_SRC="$DESKTOP/dist-release/intercom-$BASE.tar.gz"
WIN_SRC="$DESKTOP/dist-win/InterCom-Setup-x64.exe"
[[ -f "$LINUX_SRC" ]] || die "missing $LINUX_SRC"
[[ -f "$WIN_SRC" ]] || die "missing $WIN_SRC"
rm -rf "$OUT"
mkdir -p "$OUT"
LINUX_ASSET="InterCom-$VERSION-linux-x64.tar.gz"
WIN_ASSET="InterCom-Setup-$VERSION-x64.exe"
cp "$LINUX_SRC" "$OUT/$LINUX_ASSET"
cp "$WIN_SRC" "$OUT/$WIN_ASSET"
(cd "$OUT" && sha256sum "$LINUX_ASSET" "$WIN_ASSET" >SHA256SUMS)
cat "$OUT/SHA256SUMS"
ls -l "$OUT"

if ((!PUBLISH)); then
    echo
    echo "Assets are in $OUT. Nothing was committed, tagged or pushed (--no-publish)."
    exit 0
fi

step "Submodule pointers"
git add "${FORKS[@]}"
if ! git diff --cached --quiet; then
    git commit -m "Release $VERSION"
fi

step "Tags"
for fork in "${FORKS[@]}"; do
    git -C "$fork" tag -a "$FORK_TAG" -m "InterCom $VERSION"
done
git tag -a "$TAG" -m "InterCom $VERSION"

step "Push"
for fork in "${FORKS[@]}"; do
    remote="$(fork_remote "$fork")"
    git -C "$fork" push "$remote" intercom "refs/tags/$FORK_TAG"
done
git push origin main "refs/tags/$TAG"

step "GitHub release"
notes >"$OUT/notes.md"
gh release create "$TAG" --repo "$REPO" --verify-tag \
    --title "InterCom $VERSION" --notes-file "$OUT/notes.md" \
    "$OUT/$LINUX_ASSET" "$OUT/$WIN_ASSET" "$OUT/SHA256SUMS"
gh release view "$TAG" --repo "$REPO"
