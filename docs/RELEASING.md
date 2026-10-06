# Releasing Join!

Releases are published on the repository's [Releases page](https://github.com/Poliuk/join/releases). Each one carries `Join.zip`: a universal Join.app (Apple silicon and Intel), ad-hoc signed, not notarized. This link always downloads the newest release:

https://github.com/Poliuk/join/releases/latest/download/Join.zip

## Branches and tags

Commits never publish a release by themselves. Only a version tag does.

- **`main` is always releasable.** CI (`.github/workflows/ci.yml`) builds, tests and packages every push to main and every pull request. If main goes red, fixing it comes before anything else.
- **Work happens on short-lived branches** (`feature/…`, `fix/…`), merged into main through a pull request once CI is green. Small changes can go straight to main.
- **A push to main only runs CI.** That run's universal Join.app is kept, zipped, as a workflow artifact for 90 days (Actions › the run › Artifacts; unzip the download, then `Join.zip` inside it), which is handy for trying a change before it ships. It isn't a release.
- **A release is a tag `vMAJOR.MINOR.PATCH` on a commit of main.** Pushing it runs `.github/workflows/release.yml`, which publishes the release.

This is a lighter take on git-flow. git-flow keeps a `develop` branch so that `main` only moves on releases. Here, tags do that job: nothing reaches users until a tag says so, and there's one long-lived branch to keep green instead of two to keep in sync. It also means there are no hotfix branches: a fix lands on main and goes out as a patch release. That works as long as main only holds work that's ready to ship, so keep unfinished work on its branch until it is.

## Version numbers

[Semantic versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

- **PATCH** (1.0.0 → 1.0.1): bug fixes only.
- **MINOR** (1.0.1 → 1.1.0): new features or settings, nothing removed.
- **MAJOR** (1.1.0 → 2.0.0): something users rely on changes or goes away, such as dropping support for a macOS version.

The version lives in `Resources/Info.plist`. `CFBundleShortVersionString` and `CFBundleVersion` are both set to it.

## Cutting a release

1. Make sure main is green on [Actions](https://github.com/Poliuk/join/actions/workflows/ci.yml).
2. Run, from an up-to-date main with a clean working tree:

   ```sh
   make release VERSION=1.1.0
   ```

   `scripts/release.sh` checks that you're on main, the tree is clean, main isn't behind origin, and the version is newer than the last release. It then writes the version into both keys of `Info.plist`, commits "Release 1.1.0" (unless `Info.plist` already had it), tags `v1.1.0`, and asks before pushing main and the tag together. Answer anything but `y` and nothing leaves your Mac; it prints how to push or undo.
3. GitHub runs the [Release workflow](https://github.com/Poliuk/join/actions/workflows/release.yml), which takes about three minutes. It checks the tag matches `Info.plist` and is on main, runs the tests, builds the universal app, zips it with `ditto`, and creates the release "Join! 1.1.0" with `Join.zip` attached. The notes start with the commits since the previous release, followed by GitHub's generated part: merged pull requests, new contributors and a link to the full comparison. Edit them on the release page if you like; the first release only says it's the first, so write a short summary there.

## When something goes wrong

- **The Release workflow failed before publishing** (a test, the build): fix it on main, delete the tag, and release the same version again. The script notices `Info.plist` already has the version and only re-tags:

  ```sh
  git push --delete origin v1.1.0 && git tag -d v1.1.0
  make release VERSION=1.1.0
  ```

  If the failure looks flaky, use **Re-run jobs** on the failed run instead.
- **Another clone still has the old tag:** after a tag is made again, your other checkouts keep the old one, and the script stops with "couldn't fetch origin". Run `git fetch --tags --force origin` there once.
- **A job fails before its first step with an error about the runner image:** GitHub retires old macOS runner images (`macos-14` goes on 2 November 2026, with deliberate failures on some days before that). Re-running won't help. Change `runs-on` in both workflows to a newer `macos-N` label, push to main, and let CI pass before tagging.
- **A bad build went out:** don't replace it. Fix main and release a patch (1.1.1). If it's bad enough, mark the broken release as a pre-release or delete it on GitHub, so `latest` points at the previous one until the fix ships.

## Installing a release

The [README](../README.md#install) has the steps. Because the app isn't notarized, macOS blocks the first launch of each downloaded version until you click **Open Anyway** in System Settings › Privacy & Security. The calendar permission carries over between versions, because the signature's designated requirement is the bundle identifier.

Notarization would remove that step. It needs a paid Apple Developer account, a Developer ID certificate in the workflow's secrets, and a `notarytool` step before the zip.
