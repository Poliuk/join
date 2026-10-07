#!/bin/sh
# Cuts a release: sets the version in Info.plist, commits it, tags vX.Y.Z on main and pushes both.
# The tag starts .github/workflows/release.yml, which builds Join.app and publishes it on GitHub.
# Commits without a tag are never released. See docs/RELEASING.md.
#   scripts/release.sh 1.1.0     # or: make release VERSION=1.1.0
set -eu
cd "$(dirname "$0")/.."

fail() { echo "error: $*" >&2; exit 1; }

VERSION="${1:-}"
# AppVersion's rule: three numbers without leading zeros. Installed copies never offer a release whose
# tag breaks it, and a build with such a version never checks for updates.
echo "$VERSION" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ||
    fail "usage: scripts/release.sh MAJOR.MINOR.PATCH (numbers without leading zeros)"
TAG="v$VERSION"
PLIST=Resources/Info.plist

[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || fail "releases are cut from main"
[ -z "$(git status --porcelain)" ] || fail "commit or stash your changes first"
git fetch --quiet --tags origin main ||
    fail "couldn't fetch origin. If a release tag was made again there, run: git fetch --tags --force origin"
git merge-base --is-ancestor origin/main HEAD || fail "main is behind origin/main; pull first"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null && fail "$TAG is already released"
    fail "$TAG was made here but never pushed. Publish it: git push --atomic origin main $TAG, or delete it: git tag -d $TAG"
fi

# Versions only go up.
LATEST="$(git tag --list 'v*.*.*' | sed 's/^v//' | sort -V | tail -n 1)"
if [ -n "$LATEST" ] && [ "$(printf '%s\n%s\n' "$LATEST" "$VERSION" | sort -V | tail -n 1)" != "$VERSION" ]; then
    fail "$VERSION isn't newer than the latest release, $LATEST"
fi

# The bundle's version and build number are both the release's version. Info.plist may already
# have it, after a release whose tag was deleted to try again; then there's nothing to commit.
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$VERSION" "$PLIST"
UNDO="git tag -d $TAG"
if ! git diff --quiet -- "$PLIST"; then
    git commit --quiet -m "Release $VERSION" "$PLIST"
    UNDO="$UNDO && git reset --hard HEAD~1"
fi
git tag -a "$TAG" -m "Join! $VERSION"

echo "Tagged $(git log -1 --format='%h %s') as $TAG."
printf 'Push main and %s to origin and publish the release? [y/N] ' "$TAG"
read -r ANSWER || ANSWER=
case "$ANSWER" in
    [yY]*) ;;
    *)
        echo "Not pushed. To publish later: git push --atomic origin main $TAG"
        echo "To undo: $UNDO"
        exit 1
        ;;
esac
if ! git push --atomic origin main "$TAG"; then
    echo "Push failed; nothing was published. To try again: git push --atomic origin main $TAG" >&2
    echo "To undo: $UNDO" >&2
    exit 1
fi
echo "Pushed. GitHub is building the release: https://github.com/Poliuk/join/actions/workflows/release.yml"
