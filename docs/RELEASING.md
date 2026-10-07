# Releasing Join!

Releases are published on the repository's [Releases page](https://github.com/Poliuk/join/releases). Each one carries `Join.zip`: a universal Join.app (Apple silicon and Intel), ad-hoc signed, not notarized. Installed copies of Join! 1.1.0 and later check for a new release once a day and offer to install it, so users see a new release within a day of it being published. This link always downloads the newest release:

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
- **MAJOR** (1.1.0 → 2.0.0): something users rely on changes or goes away, such as dropping support for a macOS version. Copies on the dropped macOS are still offered that release, because GitHub's API doesn't say which macOS a release needs. When the user clicks Install, Join! downloads it, sees its `LSMinimumSystemVersion` and stops: Settings › General › Updates then says "Join! 2.0.0 needs macOS 15.0 or later", the update bar goes away, and that release isn't offered again. A later release is offered as usual, and ends the same way if it needs the newer macOS too.

The version lives in `Resources/Info.plist`. `CFBundleShortVersionString` and `CFBundleVersion` are both set to it.

Installed copies compare these numbers to decide whether a release is newer than theirs. They only consider GitHub's latest release, so drafts and pre-releases are never offered, and only a tag of exactly `vX.Y.Z` (no leading zeros, no suffix) with a `Join.zip` asset counts. `scripts/release.sh` and the Release workflow refuse any other version, since installed copies would never offer it and a build with such a version never checks for updates.

## Cutting a release

1. Make sure main is green on [Actions](https://github.com/Poliuk/join/actions/workflows/ci.yml).
2. Run, from an up-to-date main with a clean working tree:

   ```sh
   make release VERSION=1.1.0
   ```

   `scripts/release.sh` checks that the version is three numbers without leading zeros, you're on main, the tree is clean, main isn't behind origin, and the version is newer than the last release. It then writes the version into both keys of `Info.plist`, commits "Release 1.1.0" (unless `Info.plist` already had it), tags `v1.1.0`, and asks before pushing main and the tag together. Answer anything but `y` and nothing leaves your Mac; it prints how to push or undo.
3. GitHub runs the [Release workflow](https://github.com/Poliuk/join/actions/workflows/release.yml), which takes about three minutes. It checks the tag is `vMAJOR.MINOR.PATCH` without leading zeros, matches `Info.plist` and is on main, runs the tests, builds the universal app, zips it with `ditto`, and creates the release "Join! 1.1.0" with `Join.zip` attached. The notes start with the commits since the previous release, followed by GitHub's generated part: merged pull requests, new contributors and a link to the full comparison. Edit them on the release page if you like; the first release only says it's the first, so write a short summary there. Within a day, installed copies that have the updater (1.1.0 and later) show "Join! x.y.z is available" in the menu bar panel.

## When something goes wrong

- **The Release workflow failed before publishing** (a test, the build): fix it on main, delete the tag, and release the same version again. The script notices `Info.plist` already has the version and only re-tags:

  ```sh
  git push --delete origin v1.1.0 && git tag -d v1.1.0
  make release VERSION=1.1.0
  ```

  If the failure looks flaky, use **Re-run jobs** on the failed run instead.
- **Another clone still has the old tag:** after a tag is made again, your other checkouts keep the old one, and the script stops with "couldn't fetch origin". Run `git fetch --tags --force origin` there once.
- **A job fails before its first step with an error about the runner image:** GitHub retires old macOS runner images (`macos-14` goes on 2 November 2026, with deliberate failures on some days before that). Re-running won't help. Change `runs-on` in both workflows to a newer `macos-N` label, push to main, and let CI pass before tagging.
- **A bad build went out:** installed copies start offering it within a day, so act quickly. Delete the broken release on GitHub (**Delete** on its page, or `gh release delete v1.1.0`). That keeps the tag, so the version can't be released again by mistake, and it stops installs at once: `latest` and the `releases/latest/download/Join.zip` link fall back to the previous release, no check offers the bad one any more, and an Install already on offer fails at the download. Marking the release a pre-release isn't enough: it only stops new offers, and copies that already found it keep offering it, with an Install that still downloads its `Join.zip`, until their next check (daily, or when Join! relaunches). Don't delete only its `Join.zip` either: the release would stay `latest`, and the README's download link would break. Then fix main and release a patch (1.1.1). Copies that already installed the bad build get the fix with that patch, offered like any other release; the app never offers an older version, so moving `latest` back doesn't undo their install. Don't publish a fixed build under the bad one's version: those copies already have that version, so they would never be offered it. If the bad build broke updating itself, its users have to download the patch by hand, as 1.0.0 users do.

## Installing a release

The [README](../README.md#install) has the steps. Because the app isn't notarized, macOS blocks the first launch of each version you download yourself until you click **Open Anyway** in System Settings › Privacy & Security. From 1.1.0 on, that's only needed once: Join! downloads later versions itself when you click **Install** in the menu bar panel or in Settings › General › Updates, and a download made by the app isn't quarantined. It checks the download, replaces the app and relaunches, or, when it can't replace itself, puts the new version in `~/Downloads` and asks you to quit Join! and move it to Applications. 1.0.0 has no updater, so copies on it are updated by hand once. The calendar permission carries over between versions, because the signature's designated requirement is the bundle identifier. How the updater works and what it trusts is in [Updates](TECHNICAL_DESIGN.md#14-updates) in the technical design.

Notarization would remove that step. It needs a paid Apple Developer account, a Developer ID certificate in the workflow's secrets, and a `notarytool` step before the zip.
