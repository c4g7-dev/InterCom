#!/usr/bin/env bash
# Collects and publishes a release of Lattice for Android (called InterCom for Android up to 26.11.1-intercom.14).
#
#   tools/android-release.sh <version> [--build] [--no-publish] [--prerelease] [--bridge <version>]
#
#   <version>      e.g. 26.11.1-intercom.15: the Element X version the app is based on, then the
#                  revision (1 to 79, the same as the desktop release of the round; "intercom"
#                  in it is part of the version's format, which the installed apps parse, and
#                  stays). CHANGELOG.md must have a "## Android <version>" section.
#   --build        build the app first (element-x-android, :app:assembleFdroidRelease). The RTC
#                  core and the call library must already be in ~/.m2, see docs/BUILDING.md.
#                  Without it, the APK that is already built is taken.
#   --no-publish   collect the files in release/android-<version>/ and stop: no commit, no tag,
#                  no push, no GitHub release
#   --prerelease   mark the GitHub release as a pre-release; the app offers it only to those
#                  who turned on "Offer pre-releases"
#   --bridge <v>   also publish the same APK as release android-v<v>, for the installs that
#                  cannot read this release's tag: 26.11.1-intercom.7 and older understand a
#                  revision of one digit only, so they do not see android-v26.11.1-intercom.14.
#                  `--bridge 26.11.1-intercom.9` gives them a release they do see; its
#                  android-update.json names the bridge's version and file but the version code
#                  of the real APK, which is what they compare and check. Once on the new
#                  version they follow the ordinary releases. <v> must sort below <version>.
#
# What it does:
#   1. checks the APK: package, version name and version code as expected for <version>, one
#      signer, the same certificate as the release before (ANDROID_CERT_SHA256 below), arm64-v8a
#      only, and no path of this machine in InterCom's own native library
#   2. writes to release/android-<version>/:
#        Lattice-Android-<version>-arm64-v8a.apk    the APK under the app's name
#        InterCom-Android-<version>-arm64-v8a.apk   the same file under the name it had before:
#                              26.11.1-intercom.14 and older take a release only if it has the
#                              APK under exactly this name, and android-update.json naming it
#        android-update.json   what the app's updater reads, see below
#        SHA256SUMS            over all three
#        notes.md              the section of CHANGELOG.md
#   3. commits the submodule pointers, tags this repository android-v<version> and the three
#      forks intercom-android-v<version>, pushes branches and tags
#   4. creates the GitHub release as a draft, uploads the files, then publishes it, never as
#      "latest": that is the desktop's newest release, which the desktop app's updater and
#      the README's download links follow.
#
# android-update.json (the app's updater, element-x-android/features/intercomupdate):
#   {
#     "schema": 1,
#     "package": "com.c4g7.intercom.android",
#     "versionCode": 2026110124,          what Android compares; read from the APK
#     "versionName": "26.11.1-intercom.4",
#     "abi": "arm64-v8a",
#     "minSdk": 24,
#     "apk": "InterCom-Android-26.11.1-intercom.4-arm64-v8a.apk",   a file of the same release;
#                                         the old name, which every version accepts: the ones
#                                         from 26.11.1-intercom.15 on download whichever of the
#                                         two names this states
#     "size": 130000000,
#     "sha256": "<of the APK, hex>",
#     "notes": "<plain text shown in the app>"
#   }
# The releases stay in the repository c4g7-dev/InterCom, under its old name: the installed
# apps up to 26.11.1-intercom.14 accept only download addresses below
# https://github.com/c4g7-dev/InterCom/releases/download/, and GitHub's API gives a renamed
# repository's files under its new name, so a rename would cut every one of them off from
# updates. From 26.11.1-intercom.15 on the app also accepts c4g7-dev/Lattice.
#
# The app lists the repository's releases, takes the tags android-v<version> (not drafts; pre-
# releases only on request), orders them by the version in the tag and reads this file of the
# newest one that is newer than itself. The version code in the file is what counts; the one
# derived from the tag, ((2000+yy)*10000 + mm*100 + n)*100 + 20 + revision, only orders the
# list. (20 is the ABI digit of arm64-v8a, the only APK there is; a revision of two digits runs
# into it, which keeps the codes rising: 2026110127 for revision 7, 2026110134 for 14, up to
# revision 79.) A release without this file is still understood through SHA256SUMS.
#
# Needs: git, gh (logged in), sha256sum, python3, and the Android SDK build tools (aapt2,
# apksigner) under ANDROID_HOME. For --build also what docs/BUILDING.md lists, and the signing
# key in the environment (INTERCOM_ANDROID_STOREFILE and the three beside it).
# The app is never installed or started.
#
# Environment:
#   INTERCOM_REPO          GitHub repository of the release (default: from the origin remote)
#   ANDROID_CERT_SHA256    SHA-256 of the certificate every release is signed with
#   GRADLE_ARGS            extra arguments for the build, e.g. "--max-workers=4"
set -euo pipefail

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
die() { echo "android-release: $*" >&2; exit 1; }

# The certificate of android-v26.11.1-intercom.1 and every release since. An APK signed with
# another key does not install over them, so it is never published.
ANDROID_CERT_SHA256="${ANDROID_CERT_SHA256:-a823f39d8eddd31affbbee21ef8eeab99c4d36c7f3b119cdb559e6ef51c4d4cc}"
PACKAGE="com.c4g7.intercom.android"
ABI="arm64-v8a"

VERSION=""
BUILD=0
PUBLISH=1
PRERELEASE=0
BRIDGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage; exit 0 ;;
        --build) BUILD=1 ;;
        --no-publish) PUBLISH=0 ;;
        --prerelease) PRERELEASE=1 ;;
        --bridge) BRIDGE="${2:-}"; shift ;;
        -*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) VERSION="$1" ;;
    esac
    shift
done
VERSION_RE='^([0-9]{2})\.([0-9]{1,2})\.([0-9]{1,2})-intercom\.([1-9][0-9]?)$'
if [[ -n "$BRIDGE" ]]; then
    [[ "$BRIDGE" =~ $VERSION_RE ]] || { echo "--bridge needs a version, e.g. 26.11.1-intercom.9" >&2; exit 2; }
    BRIDGE_REVISION="${BASH_REMATCH[4]}"
    BRIDGE_BASE="${BRIDGE%-intercom.*}"
fi
if [[ ! "$VERSION" =~ $VERSION_RE ]] || ((BASH_REMATCH[4] > 79)); then
    echo "Usage: tools/android-release.sh <version> [--build] [--no-publish] [--prerelease] [--bridge <version>]   (e.g. 26.11.1-intercom.14; the revision is 1 to 79)" >&2
    exit 2
fi
if [[ -n "$BRIDGE" ]]; then
    [[ "$BRIDGE_BASE" == "${VERSION%-intercom.*}" ]] && ((BRIDGE_REVISION < BASH_REMATCH[4])) ||
        { echo "--bridge $BRIDGE must be of the same Element X version as $VERSION and of a lower revision" >&2; exit 2; }
fi
# As plugins/src/main/kotlin/Versions.kt and app/build.gradle.kts of element-x-android compute it.
EXPECTED_CODE=$(( ((2000 + 10#${BASH_REMATCH[1]}) * 10000 + 10#${BASH_REMATCH[2]} * 100 + 10#${BASH_REMATCH[3]}) * 100 + 20 + BASH_REMATCH[4] ))

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TAG="android-v$VERSION"
FORK_TAG="intercom-android-v$VERSION"
FORKS=(matrix-rust-rtc element-call-android element-x-android)
REPO="${INTERCOM_REPO:-$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')}"
OUT="$ROOT/release/android-$VERSION"
# The name the manifest states, and the only one 26.11.1-intercom.14 and older look for.
APK_NAME="InterCom-Android-$VERSION-$ABI.apk"
# The same file under the app's name, for people who download it.
LATTICE_APK_NAME="Lattice-Android-$VERSION-$ABI.apk"
BUILT_APK="element-x-android/app/build/outputs/apk/fdroid/release/app-fdroid-$ABI-release.apk"

# The section of CHANGELOG.md for this version, without its heading
notes() {
    awk -v h="## Android $VERSION" '
        $0 == h { on = 1; next }
        on && /^## / { exit }
        on { print }
    ' CHANGELOG.md | sed -e '/./,$!d'
}
[[ -n "$(notes)" ]] || die "CHANGELOG.md has no section '## Android $VERSION'"

BUILD_TOOLS="$(ls -d "${ANDROID_HOME:?ANDROID_HOME is not set}"/build-tools/* | sort -V | tail -1)"
[[ -x "$BUILD_TOOLS/aapt2" && -x "$BUILD_TOOLS/apksigner" ]] || die "no aapt2 and apksigner in $BUILD_TOOLS"

if [[ $BUILD == 1 ]]; then
    [[ -n "${INTERCOM_ANDROID_STOREFILE:-}" ]] || die "--build needs the signing key in the environment (INTERCOM_ANDROID_STOREFILE, ...)"
    # shellcheck disable=SC2086
    (cd element-x-android && ./gradlew :app:assembleFdroidRelease ${GRADLE_ARGS:-})
fi
[[ -f "$BUILT_APK" ]] || die "$BUILT_APK is not built (see docs/BUILDING.md, or pass --build)"

echo "== Checking $BUILT_APK"
badging="$("$BUILD_TOOLS/aapt2" dump badging "$BUILT_APK")"
field() { sed -n "s/^package:.* $1='\([^']*\)'.*/\1/p" <<<"$badging"; }
[[ "$(field name)" == "$PACKAGE" ]] || die "the APK is $(field name), not $PACKAGE"
[[ "$(field versionName)" == "$VERSION" ]] || die "the APK is version $(field versionName), not $VERSION"
VERSION_CODE="$(field versionCode)"
[[ "$VERSION_CODE" == "$EXPECTED_CODE" ]] || die "the APK has version code $VERSION_CODE, expected $EXPECTED_CODE for $VERSION"
MIN_SDK="$(sed -n "s/^minSdkVersion:'\([0-9]*\)'.*/\1/p" <<<"$badging")"
[[ "$(sed -n "s/^native-code: //p" <<<"$badging")" == "'$ABI'" ]] || die "the APK is not for $ABI alone"

signers="$("$BUILD_TOOLS/apksigner" verify --print-certs --verbose "$BUILT_APK")" || die "the APK's signature does not verify"
# One line per signature scheme, all of the same certificate.
cert="$(sed -n 's/^.*certificate SHA-256 digest: //p' <<<"$signers" | sort -u)"
[[ "$cert" == "$ANDROID_CERT_SHA256" ]] || die "the APK is signed with $cert, the releases with $ANDROID_CERT_SHA256: it would not install over them"
grep -q '^Number of signers: 1$' <<<"$signers" || die "the APK does not have exactly one signer"
for scheme in "v2 scheme (APK Signature Scheme v2)" "v3 scheme (APK Signature Scheme v3)"; do
    grep -q "^Verified using $scheme: true" <<<"$signers" || die "the APK is not signed with the $scheme"
done

# InterCom's own native library must not name this machine. (The libraries of other projects
# name the machines of their own builds, GitHub's runners.)
if unzip -p "$BUILT_APK" "lib/$ABI/libmatrix_rtc_ffi.so" | LC_ALL=C grep -a -q -e "$HOME" -e "/home/"; then
    die "libmatrix_rtc_ffi.so names a directory of this machine; rebuild the core with matrix-rust-rtc/scripts/build-intercom-android.sh"
fi
if unzip -p "$BUILT_APK" | LC_ALL=C grep -a -q -F -e "$HOME/"; then
    die "the APK contains the path $HOME/"
fi

echo "== Collecting the files in $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$BUILT_APK" "$OUT/$APK_NAME"
cp "$BUILT_APK" "$OUT/$LATTICE_APK_NAME"
notes >"$OUT/notes.md"
VERSION="$VERSION" VERSION_CODE="$VERSION_CODE" MIN_SDK="$MIN_SDK" PACKAGE="$PACKAGE" ABI="$ABI" APK_NAME="$APK_NAME" OUT="$OUT" python3 - <<'PY'
import hashlib, json, os, re

out = os.environ["OUT"]
apk = os.path.join(out, os.environ["APK_NAME"])
digest = hashlib.sha256()
with open(apk, "rb") as f:
    for block in iter(lambda: f.read(1 << 20), b""):
        digest.update(block)

# The app shows the notes as plain text: the items of the changelog's list, without their
# markup, up to the known limitations.
lines = []
for line in open(os.path.join(out, "notes.md"), encoding="utf-8").read().split("\n"):
    if re.match(r"- (Known limitations|\*\*Not tested)", line):
        break
    lines.append(line)
text = "\n".join(lines)
text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text).replace("`", "")
paragraphs = [" ".join(p.split()) for p in re.split(r"\n\s*\n|\n(?=- )", text) if p.strip()]
notes = "\n\n".join(p.replace("- ", "• ", 1) for p in paragraphs if p.startswith("- "))

manifest = {
    "schema": 1,
    "package": os.environ["PACKAGE"],
    "versionCode": int(os.environ["VERSION_CODE"]),
    "versionName": os.environ["VERSION"],
    "abi": os.environ["ABI"],
    "minSdk": int(os.environ["MIN_SDK"]),
    "apk": os.environ["APK_NAME"],
    "size": os.path.getsize(apk),
    "sha256": digest.hexdigest(),
    "notes": notes,
}
with open(os.path.join(out, "android-update.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
(cd "$OUT" && sha256sum "$LATTICE_APK_NAME" "$APK_NAME" android-update.json >SHA256SUMS)
cmp -s "$OUT/$APK_NAME" "$OUT/$LATTICE_APK_NAME" || die "the two names are not the same APK"
# What 26.11.1-intercom.14 and older require of a release, which no later change may break.
python3 - "$OUT/android-update.json" "$APK_NAME" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
if manifest["apk"] != sys.argv[2]:
    sys.exit(f"android-update.json names {manifest['apk']}, the installed apps need {sys.argv[2]}")
PY
ls -l "$OUT"
cat "$OUT/SHA256SUMS"

# The bridge: the same APK under the name an old install expects for the tag it can read.
if [[ -n "$BRIDGE" ]]; then
    BRIDGE_TAG="android-v$BRIDGE"
    BRIDGE_OUT="$OUT/bridge-$BRIDGE"
    BRIDGE_APK="InterCom-Android-$BRIDGE-$ABI.apk"
    mkdir -p "$BRIDGE_OUT"
    cp "$OUT/$APK_NAME" "$BRIDGE_OUT/$BRIDGE_APK"
    VERSION="$VERSION" BRIDGE="$BRIDGE" BRIDGE_APK="$BRIDGE_APK" OUT="$OUT" BRIDGE_OUT="$BRIDGE_OUT" python3 - <<'PY'
import json, os

manifest = json.load(open(os.path.join(os.environ["OUT"], "android-update.json"), encoding="utf-8"))
version, bridge = os.environ["VERSION"], os.environ["BRIDGE"]
# The version code, the size and the checksum stay those of the real APK.
manifest["versionName"] = bridge
manifest["apk"] = os.environ["BRIDGE_APK"]
manifest["notes"] = f"This installs Lattice {version}.\n\n" + manifest["notes"]
with open(os.path.join(os.environ["BRIDGE_OUT"], "android-update.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
    {
        echo "**This is Lattice $VERSION** under a tag that InterCom for Android 26.11.1-intercom.7 and older can read:"
        echo "they understand a revision of one digit only, so they do not see \`$TAG\`. The APK is the same file as"
        echo "[\`$LATTICE_APK_NAME\`](https://github.com/$REPO/releases/tag/$TAG); installing it gives $VERSION, which then"
        echo "follows the ordinary releases. For a new installation take [$TAG](https://github.com/$REPO/releases/tag/$TAG)."
        echo
        cat "$OUT/notes.md"
    } >"$BRIDGE_OUT/notes.md"
    (cd "$BRIDGE_OUT" && sha256sum "$BRIDGE_APK" android-update.json >SHA256SUMS)
    cmp -s "$OUT/$APK_NAME" "$BRIDGE_OUT/$BRIDGE_APK" || die "the bridge's APK is not the release's"
    ls -l "$BRIDGE_OUT"
fi

if [[ $PUBLISH == 0 ]]; then
    echo "== Not publishing (--no-publish)"
    exit 0
fi

echo "== Tagging and pushing"
for fork in "${FORKS[@]}"; do
    [[ -z "$(git -C "$fork" status --porcelain)" ]] || die "$fork has uncommitted changes"
    git -C "$fork" tag -f "$FORK_TAG"
    git -C "$fork" push origin HEAD:refs/heads/intercom "refs/tags/$FORK_TAG"
done
# Only the three pointers: the desktop's submodules and files may be in the middle of their own
# work in this checkout, which is also why the pull stashes what is not committed.
git add "${FORKS[@]}"
git diff --cached --quiet -- "${FORKS[@]}" || git commit -m "Android $VERSION: submodule pointers" -- "${FORKS[@]}"
# The release notes are this version's section, which must be committed as it is here; the
# desktop's sections of the same file may be in the middle of their own work.
committed_notes="$(git show HEAD:CHANGELOG.md | awk -v h="## Android $VERSION" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' | sed -e '/./,$!d')"
[[ "$committed_notes" == "$(notes)" ]] || die "the section '## Android $VERSION' of CHANGELOG.md is not committed as it is; the release notes come from it"
# The desktop's releases are pushed to the same branch.
git pull --rebase --autostash origin main
git tag -f "$TAG"
git push origin HEAD:main "refs/tags/$TAG"

echo "== Publishing $TAG on $REPO"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release edit "$TAG" --repo "$REPO" --title "[Android] Lattice $VERSION · arm64" --notes-file "$OUT/notes.md"
else
    # A draft until its files are on it: the app must never find a release without them.
    gh release create "$TAG" --repo "$REPO" --verify-tag --draft --latest=false \
        --title "[Android] Lattice $VERSION · arm64" --notes-file "$OUT/notes.md"
fi
gh release upload "$TAG" --repo "$REPO" --clobber "$OUT/$LATTICE_APK_NAME" "$OUT/$APK_NAME" "$OUT/android-update.json" "$OUT/SHA256SUMS"
if [[ $PRERELEASE == 1 ]]; then
    gh release edit "$TAG" --repo "$REPO" --draft=false --prerelease --latest=false
else
    gh release edit "$TAG" --repo "$REPO" --draft=false --latest=false
fi
gh release view "$TAG" --repo "$REPO"

if [[ -n "$BRIDGE" ]]; then
    echo "== Publishing the bridge $BRIDGE_TAG"
    git tag -f "$BRIDGE_TAG" "$TAG^{commit}"
    git push origin "refs/tags/$BRIDGE_TAG"
    BRIDGE_TITLE="[Android] Lattice $VERSION · arm64 (for 26.11.1-intercom.7 and older)"
    if gh release view "$BRIDGE_TAG" --repo "$REPO" >/dev/null 2>&1; then
        gh release edit "$BRIDGE_TAG" --repo "$REPO" --title "$BRIDGE_TITLE" --notes-file "$BRIDGE_OUT/notes.md"
    else
        gh release create "$BRIDGE_TAG" --repo "$REPO" --verify-tag --draft --latest=false \
            --title "$BRIDGE_TITLE" --notes-file "$BRIDGE_OUT/notes.md"
    fi
    gh release upload "$BRIDGE_TAG" --repo "$REPO" --clobber "$BRIDGE_OUT/$BRIDGE_APK" "$BRIDGE_OUT/android-update.json" "$BRIDGE_OUT/SHA256SUMS"
    if [[ $PRERELEASE == 1 ]]; then
        gh release edit "$BRIDGE_TAG" --repo "$REPO" --draft=false --prerelease --latest=false
    else
        gh release edit "$BRIDGE_TAG" --repo "$REPO" --draft=false --latest=false
    fi
    gh release view "$BRIDGE_TAG" --repo "$REPO"
fi
