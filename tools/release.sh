#!/usr/bin/env bash
# Builds and publishes a Lattice desktop release. (The app was called InterCom up to
# 1.12.35-intercom.14; version numbers, tags, branches and this repository keep that name.)
#
#   tools/release.sh <version> --ci
#   tools/release.sh <version> [--skip-build] [--no-publish]
#
#   <version>      e.g. 1.12.35-intercom.15: the Element Web version Lattice is based on, then
#                  Lattice's revision, still written "intercom.N": every install compares these
#                  numbers and finds the releases by their tags, and the ones from before the
#                  rename read nothing else. CHANGELOG.md must have a "## <version>" section.
#   --ci           build nothing here: commit the submodule pointers, tag and push, and let the
#                  release workflow (.github/workflows/release.yml) build both targets and
#                  publish the GitHub release. Needs GitHub Actions to be usable for the account.
#   --skip-build   reuse the builds already in element-web/apps/desktop/{dist-release,dist-win}
#   --no-publish   build and collect the assets in release/<version>/, then stop: no commit, no
#                  tag, no push, no GitHub release
#
# What it does without --ci:
#   1. builds Element Call (embedded), the web app, the Linux app and the Windows installer,
#      one heavy step at a time
#   2. collects Lattice-<version>-linux-x64.tar.gz and Lattice-Setup-<version>-x64.exe, the same
#      two files under the names from before the rename (InterCom-<version>-linux-x64.tar.gz,
#      InterCom-Setup-<version>-x64.exe), and SHA256SUMS of all four in release/<version>/
#   3. commits the submodule pointers, tags this repository v<version> and the two forks
#      intercom-v<version>, and pushes branches and tags
#   4. creates or updates the GitHub release with the notes from CHANGELOG.md; files already
#      on it are kept, and SHA256SUMS covers all of them. A new release is a draft until its
#      files are on it.
#
# The app updates itself from these releases (element-web/apps/desktop/src/intercom-updater.ts):
# it needs the tag v<version>, this platform's file under a name it knows and SHA256SUMS, and it
# knows its own version from INTERCOM_VERSION, which this script sets for the build. Installs up
# to 1.12.35-intercom.14 know only the InterCom-… names, newer ones take Lattice-… first: leave
# the old names out (LATTICE_LEGACY_ASSETS=0) only when no install that old is to be updated.
#
# Before a release, go through docs/RELEASING.md: the changelog, the README, the list of changes
# and the screenshots are part of it. The script warns, and goes on, when README.md or
# docs/CHANGES-FROM-ELEMENT.md did not change since the last release tag.
#
# Needs: git, node and gh (logged in); for a local build also pnpm 12, wine (Windows installer)
# and sha256sum.
# The built application is never started.
#
# Environment:
#   INTERCOM_REPO      GitHub repository of the release (default: taken from the origin remote)
#   LATTICE_LEGACY_ASSETS  0 leaves out the copies under the InterCom-… names (default: 1)
#   INTERCOM_WINEPREFIX  wine prefix for the Windows build
#                        (default: ~/.cache/electron-builder/intercom-wine-prefix, never ~/.wine)
#   WEBPACK_JOBS       caps the minifier's workers when memory is tight
set -euo pipefail

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

VERSION=""
SKIP_BUILD=0
PUBLISH=1
CI=0
for arg in "$@"; do
    case "$arg" in
        -h | --help) usage; exit 0 ;;
        --ci) CI=1 ;;
        --skip-build) SKIP_BUILD=1 ;;
        --no-publish) PUBLISH=0 ;;
        -*) echo "Unknown option: $arg" >&2; exit 2 ;;
        *) VERSION="$arg" ;;
    esac
done
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+-intercom\.[0-9]+$ ]]; then
    echo "Usage: tools/release.sh <version> [--ci | --skip-build | --no-publish]   (e.g. 1.12.35-intercom.1)" >&2
    exit 2
fi
if ((CI && (SKIP_BUILD || !PUBLISH))); then
    echo "--ci goes with neither --skip-build nor --no-publish" >&2
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
TOOLS=(git node)
((CI)) || TOOLS+=(pnpm sha256sum)
for tool in "${TOOLS[@]}"; do
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

# The public repository is part of a release (docs/RELEASING.md): a release that changes what a
# user sees changes these two files as well. Not an error: some releases change neither.
PREVIOUS="$(git tag --list 'v[0-9]*' --sort=-v:refname | grep -vxF "$TAG" | head -n 1 || true)"
if [[ -n "$PREVIOUS" ]]; then
    STALE=()
    for doc in README.md docs/CHANGES-FROM-ELEMENT.md; do
        if git diff --quiet "$PREVIOUS" HEAD -- "$doc"; then STALE+=("$doc"); fi
    done
    if ((${#STALE[@]})); then
        {
            echo "release.sh: warning: not changed since $PREVIOUS: ${STALE[*]}"
            echo "  If this release changes what a user sees, check before going on (docs/RELEASING.md):"
            echo "    - README.md: the highlights and the comparison table"
            echo "    - docs/CHANGES-FROM-ELEMENT.md: a row for each change, with its version under \"Since\""
            echo "    - docs/UPDATES.md, docs/ANDROID.md, docs/DESIGN.md, docs/DIAGNOSTICS.md: where affected"
            echo "    - docs/images/: screenshots of what looks different, with made-up data"
            echo "    - after the push: the links and pictures of the notes and the documents answer 200"
        } >&2
    fi
fi

export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=6144}"
# Written into the app's package.json: what the built app compares with the releases on GitHub
# when it looks for an update. A build without it never updates itself.
export INTERCOM_VERSION="$VERSION"

if ((CI)); then
    [[ -f .github/workflows/release.yml ]] || die "the release workflow is missing"
elif ((!SKIP_BUILD)); then
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

if ((!CI)); then
    step "Assets"
    LINUX_SRC="$DESKTOP/dist-release/intercom-$BASE.tar.gz"
    WIN_SRC="$DESKTOP/dist-win/Lattice-Setup-x64.exe"
    [[ -f "$LINUX_SRC" ]] || die "missing $LINUX_SRC"
    [[ -f "$WIN_SRC" ]] || die "missing $WIN_SRC"
    rm -rf "$OUT"
    mkdir -p "$OUT"
    LINUX_ASSET="Lattice-$VERSION-linux-x64.tar.gz"
    WIN_ASSET="Lattice-Setup-$VERSION-x64.exe"
    cp "$LINUX_SRC" "$OUT/$LINUX_ASSET"
    cp "$WIN_SRC" "$OUT/$WIN_ASSET"
    ASSETS=("$LINUX_ASSET" "$WIN_ASSET")
    # The same files under the names the app had before it became Lattice: what the updater of
    # an install up to 1.12.35-intercom.14 looks for, in the release and in SHA256SUMS
    if [[ "${LATTICE_LEGACY_ASSETS:-1}" != "0" ]]; then
        LEGACY_LINUX_ASSET="InterCom-$VERSION-linux-x64.tar.gz"
        LEGACY_WIN_ASSET="InterCom-Setup-$VERSION-x64.exe"
        cp "$LINUX_SRC" "$OUT/$LEGACY_LINUX_ASSET"
        cp "$WIN_SRC" "$OUT/$LEGACY_WIN_ASSET"
        ASSETS+=("$LEGACY_LINUX_ASSET" "$LEGACY_WIN_ASSET")
    fi
    (cd "$OUT" && sha256sum "${ASSETS[@]}" >SHA256SUMS)
    cat "$OUT/SHA256SUMS"
    ls -l "$OUT"

    if ((!PUBLISH)); then
        echo
        echo "Assets are in $OUT. Nothing was committed, tagged or pushed (--no-publish)."
        exit 0
    fi
fi

step "Submodule pointers"
# Only the two pointers, whatever else is staged
if ! git diff --quiet HEAD -- "${FORKS[@]}"; then
    git commit -m "Release $VERSION" -- "${FORKS[@]}"
fi

step "Tags"
for fork in "${FORKS[@]}"; do
    git -C "$fork" tag -a "$FORK_TAG" -m "Lattice $VERSION"
done
git tag -a "$TAG" -m "Lattice $VERSION"

step "Push"
for fork in "${FORKS[@]}"; do
    remote="$(fork_remote "$fork")"
    git -C "$fork" push "$remote" intercom "refs/tags/$FORK_TAG"
done
git push origin main "refs/tags/$TAG"

if ((CI)); then
    echo
    echo "Pushed $TAG. The release workflow builds and publishes it; follow it with"
    echo "  gh run watch --repo $REPO"
    echo "  https://github.com/$REPO/actions/workflows/release.yml"
    exit 0
fi

step "GitHub release"
# Files that are on the release already (put there by other means) are kept: every file is
# uploaded on its own, and SHA256SUMS is written anew from all the files of the release.
notes >"$OUT/notes.md"
# A new release stays a draft until its files and SHA256SUMS are on it: the apps that are out
# there look for a release with this platform's file and its checksum, and a release without
# them would be offered as one to fetch by hand.
DRAFT=0
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release edit "$TAG" --repo "$REPO" --title "[Desktop] Lattice $VERSION · Linux & Windows" --notes-file "$OUT/notes.md"
else
    gh release create "$TAG" --repo "$REPO" --verify-tag --draft \
        --title "[Desktop] Lattice $VERSION · Linux & Windows" --notes-file "$OUT/notes.md"
    DRAFT=1
fi
for asset in "${ASSETS[@]}"; do
    gh release upload "$TAG" --repo "$REPO" --clobber "$OUT/$asset"
done
ALL="$(mktemp -d)"
trap 'rm -rf "$ALL"' EXIT
gh release download "$TAG" --repo "$REPO" --dir "$ALL"
rm -f "$ALL/SHA256SUMS"
(cd "$ALL" && LC_ALL=C sha256sum -- * >"$OUT/SHA256SUMS")
(cd "$OUT" && sha256sum -c SHA256SUMS --ignore-missing)
gh release upload "$TAG" --repo "$REPO" --clobber "$OUT/SHA256SUMS"
if ((DRAFT)); then
    gh release edit "$TAG" --repo "$REPO" --draft=false --latest
fi
gh release view "$TAG" --repo "$REPO"
