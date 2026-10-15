import Foundation
import Testing
@testable import JoinCore

struct UpdateCheckTests {
    static let current = AppVersion(major: 1, minor: 0, patch: 0)
    static let hex = "5b6a8afae5540e126ed053255720da7325c4532d7b802ba7878df823a5deaec7"
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Shaped like api.github.com/repos/Poliuk/join/releases/latest, with the keys Join! doesn't read
    /// left in (some trimmed).
    static let latestResponse = """
    {
      "url": "https://api.github.com/repos/Poliuk/join/releases/404967724",
      "assets_url": "https://api.github.com/repos/Poliuk/join/releases/404967724/assets",
      "upload_url": "https://uploads.github.com/repos/Poliuk/join/releases/404967724/assets{?name,label}",
      "html_url": "https://github.com/Poliuk/join/releases/tag/v1.1.0",
      "id": 404967724,
      "author": {
        "login": "github-actions[bot]",
        "id": 41898282,
        "type": "Bot",
        "site_admin": false
      },
      "node_id": "RE_kwDOU91Hec4YI1Es",
      "tag_name": "v1.1.0",
      "target_commitish": "main",
      "name": "Join! 1.1.0",
      "draft": false,
      "immutable": false,
      "prerelease": false,
      "created_at": "2026-10-07T17:09:50Z",
      "updated_at": "2026-10-07T17:12:12Z",
      "published_at": "2026-10-07T17:12:12Z",
      "assets": [
        {
          "url": "https://api.github.com/repos/Poliuk/join/releases/assets/616142104",
          "id": 616142104,
          "node_id": "RA_kwDOU91Hec4kuZUY",
          "name": "Join.zip",
          "label": "",
          "uploader": {
            "login": "github-actions[bot]",
            "id": 41898282,
            "type": "Bot",
            "site_admin": false
          },
          "content_type": "application/zip",
          "state": "uploaded",
          "size": 2486395,
          "digest": "sha256:5b6a8afae5540e126ed053255720da7325c4532d7b802ba7878df823a5deaec7",
          "download_count": 8,
          "created_at": "2026-10-07T17:12:11Z",
          "updated_at": "2026-10-07T17:12:12Z",
          "browser_download_url": "https://example.com/not-followed/Join.zip"
        },
        {
          "url": "https://api.github.com/repos/Poliuk/join/releases/assets/616142105",
          "id": 616142105,
          "name": "Join.dSYM.zip",
          "label": null,
          "content_type": "application/zip",
          "state": "uploaded",
          "size": 1048576,
          "digest": null,
          "download_count": 0,
          "browser_download_url": "https://github.com/Poliuk/join/releases/download/v1.1.0/Join.dSYM.zip"
        }
      ],
      "tarball_url": "https://api.github.com/repos/Poliuk/join/tarball/v1.1.0",
      "zipball_url": "https://api.github.com/repos/Poliuk/join/zipball/v1.1.0",
      "body": "**Full Changelog**: https://github.com/Poliuk/join/compare/v1.0.0...v1.1.0"
    }
    """

    static func release(
        tag: String = "v1.1.0",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [GitHubRelease.Asset]? = nil
    ) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            draft: draft,
            prerelease: prerelease,
            assets: assets ?? [joinZip(size: 2_486_395, digest: "sha256:" + hex)]
        )
    }

    static func joinZip(size: Int, digest: String? = nil) -> GitHubRelease.Asset {
        GitHubRelease.Asset(name: "Join.zip", size: size, digest: digest)
    }

    // MARK: Decoding

    @Test func decodesTheLatestReleaseResponse() throws {
        let decoded = try UpdateCheck.decodeRelease(Data(Self.latestResponse.utf8))
        #expect(decoded.tagName == "v1.1.0")
        #expect(!decoded.draft)
        #expect(!decoded.prerelease)
        #expect(decoded.assets == [
            GitHubRelease.Asset(name: "Join.zip", size: 2_486_395, digest: "sha256:" + Self.hex),
            GitHubRelease.Asset(name: "Join.dSYM.zip", size: 1_048_576, digest: nil),
        ])
    }

    /// Other answers GitHub gives count as a failed check, retried within the hour, never as up to date.
    @Test(arguments: [
        ("a rate limit", #"{"message": "API rate limit exceeded", "documentation_url": "https://docs.github.com/rest"}"#),
        ("a release without assets", #"{"tag_name": "v1.1.0", "draft": false, "prerelease": false}"#),
        ("an asset without a size", #"{"tag_name": "v1.1.0", "draft": false, "prerelease": false, "assets": [{"name": "Join.zip"}]}"#),
    ])
    func decodingRejectsOtherResponses(_ name: String, response: String) {
        #expect(throws: (any Error).self) {
            try UpdateCheck.decodeRelease(Data(response.utf8))
        }
    }

    // MARK: Update

    /// The URLs are built from the validated tag, never taken from the response (its download URL points
    /// at example.com).
    @Test func newerReleaseIsAnUpdateWithURLsBuiltFromTheTag() throws {
        #expect(UpdateCheck.latestReleaseURL.absoluteString == "https://api.github.com/repos/Poliuk/join/releases/latest")
        let decoded = try UpdateCheck.decodeRelease(Data(Self.latestResponse.utf8))
        let update = try #require(UpdateCheck.update(current: Self.current, release: decoded))
        #expect(update.version == AppVersion(major: 1, minor: 1, patch: 0))
        #expect(update.pageURL.absoluteString == "https://github.com/Poliuk/join/releases/tag/v1.1.0")
        #expect(update.downloadURL.absoluteString == "https://github.com/Poliuk/join/releases/download/v1.1.0/Join.zip")
        #expect(update.digest == .sha256(Self.hex))
        #expect(update.size == 2_486_395)
    }

    /// An update is a newer, published release tagged exactly vX.Y.Z (`AppVersionTests` has the other tags
    /// it rejects) with a Join.zip of 1 byte to 100 MB: the zip's size, or nil when the release isn't one.
    @Test(arguments: [
        ("the same version", release(tag: "v1.0.0"), nil),
        ("an older version", release(tag: "v0.9.9"), nil),
        ("a patch", release(tag: "v1.0.1"), 2_486_395),
        ("a major version", release(tag: "v2.0.0"), 2_486_395),
        ("a draft", release(draft: true), nil),
        ("a prerelease", release(prerelease: true), nil),
        ("a tag without its v", release(tag: "1.1.0"), nil),
        ("a tag that is a path", release(tag: "v1.1.0/../../evil"), nil),
        ("no assets", release(assets: []), nil),
        ("no asset named exactly Join.zip", release(assets: [
            GitHubRelease.Asset(name: "Join-1.1.0.zip", size: 1000), GitHubRelease.Asset(name: "join.zip", size: 1000),
        ]), nil),
        ("an empty Join.zip", release(assets: [joinZip(size: 0)]), nil),
        ("a Join.zip over 100 MB", release(assets: [joinZip(size: UpdateCheck.maximumDownloadSize + 1)]), nil),
        ("a Join.zip of exactly 100 MB", release(assets: [joinZip(size: UpdateCheck.maximumDownloadSize)]), UpdateCheck.maximumDownloadSize),
        ("Join.zip after another asset", release(assets: [GitHubRelease.Asset(name: "Join.dSYM.zip", size: 5000), joinZip(size: 1234)]), 1234),
    ] as [(String, GitHubRelease, Int?)])
    func releaseIsAnUpdate(_ name: String, release: GitHubRelease, size: Int?) {
        #expect(UpdateCheck.update(current: Self.current, release: release)?.size == size)
    }

    /// Only "sha256:" and exactly 64 hex digits give a checksum, in lowercase. A release without one, or
    /// with one that can't be read, is still an update, without a checksum; one that can't be read is kept
    /// as GitHub sent it, so the installer can log it.
    @Test(arguments: [
        ("sha256:" + hex, .sha256(hex)),
        ("sha256:" + hex.uppercased(), .sha256(hex)),
        (nil, .missing),
        ("sha512:" + hex, .unreadable("sha512:" + hex)),
        ("SHA256:" + hex, .unreadable("SHA256:" + hex)),
        ("sha256:" + hex.dropLast(), .unreadable("sha256:" + hex.dropLast())),
        ("sha256:" + hex + "0", .unreadable("sha256:" + hex + "0")),
        ("sha256:" + hex.dropLast() + "g", .unreadable("sha256:" + hex.dropLast() + "g")),
        ("sha256: " + hex.dropLast(), .unreadable("sha256: " + hex.dropLast())),
        ("", .unreadable("")),
    ] as [(String?, AvailableUpdate.Digest)])
    func digestIsAChecksumOnlyWhenItReads(_ digest: String?, expected: AvailableUpdate.Digest) throws {
        let release = Self.release(assets: [Self.joinZip(size: 1000, digest: digest)])
        let update = try #require(UpdateCheck.update(current: Self.current, release: release))
        #expect(update.digest == expected)
    }

    // MARK: Schedule

    /// Daily, an hour after a failure, and at once when the clock moved back. In hours ago; nil is never.
    @Test(arguments: [
        ("off", false, nil, nil, false),
        ("never checked", true, nil, nil, true),
        ("checked just under a day ago", true, 24 - 1.0 / 3600, nil, false),
        ("checked a day ago", true, 24, nil, true),
        ("checked in the future: the clock moved back", true, -1, nil, true),
        // Never checked is also how a launch's re-check of an offer asks (`rechecksAtLaunch`) until it succeeds.
        ("never checked, failed 10 min ago", true, nil, 10.0 / 60, false),
        ("failed just under an hour ago", true, 25, 1 - 1.0 / 3600, false),
        ("failed an hour ago", true, 25, 1, true),
        ("never checked, failed 2 h ago", true, nil, 2, true),
        ("failed 2 h ago, checked 1 h ago", true, 1, 2, false),
        ("failed in the future: the clock moved back", true, nil, -1, true),
    ] as [(String, Bool, Double?, Double?, Bool)])
    func isDue(_ name: String, enabled: Bool, hoursSinceSuccess: Double?, hoursSinceFailure: Double?, due: Bool) {
        func hoursAgo(_ hours: Double?) -> Date? {
            hours.map { Self.now.addingTimeInterval(-$0 * 3600) }
        }
        let isDue = UpdateCheck.isDue(
            enabled: enabled, lastSuccess: hoursAgo(hoursSinceSuccess), lastFailure: hoursAgo(hoursSinceFailure), now: Self.now
        )
        #expect(isDue == due)
    }

    /// At launch, a remembered offer newer than this copy is checked again at once, so it comes back without
    /// waiting a day.
    @Test(arguments: [
        ("an offer of 1.1.0", true, "1.1.0", true),
        ("automatic checks off", false, "1.1.0", false),
        ("no offer", true, nil, false),
        ("an offer of this version: updated by hand", true, "1.0.0", false),
        ("an offer of an older version", true, "0.9.0", false),
    ] as [(String, Bool, String?, Bool)])
    func rechecksAtLaunch(_ name: String, enabled: Bool, offeredVersion: String?, rechecks: Bool) {
        let offered = offeredVersion.flatMap(AppVersion.init)
        #expect(UpdateCheck.rechecksAtLaunch(enabled: enabled, offeredVersion: offered, current: Self.current) == rechecks)
    }

    // MARK: A release this Mac can't run

    /// An app's LSMinimumSystemVersion against macOS 14.6.1. One that can't be read doesn't stop an install.
    @Test(arguments: [
        ("14.0", true),
        ("14", true),
        ("14.6.1", true),
        ("14.6.2", false),
        ("15.0", false),
        ("26", false),
        ("13.5", true),
        ("", true),
        ("fifteen", true),
        ("15.x", true),
        ("15..0", true),
        ("15.0.0.1", true),
    ])
    func systemIsAtLeast(_ minimum: String, met: Bool) {
        let system = OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 1)
        #expect(UpdateCheck.system(system, isAtLeast: minimum) == met)
    }

    /// A release an install found this Mac can't run stays so until this copy or macOS catches up.
    @Test(arguments: [
        ("needs macOS 15.0, on 14.6", "1.2.0", "15.0", 14, current, true),
        ("macOS updated to 15.6", "1.2.0", "15.0", 15, current, false),
        ("this copy updated to 1.2.0", "1.2.0", "15.0", 14, AppVersion(major: 1, minor: 2, patch: 0), false),
        ("a minimum that can't be read", "1.2.0", "fifteen", 14, current, false),
    ] as [(String, String, String, Int, AppVersion, Bool)])
    func stillUnsupported(_ name: String, version: String, minimumSystem: String, macOS: Int, current: AppVersion, unsupported: Bool) throws {
        let stored = UnsupportedUpdate(version: try #require(AppVersion(version)), minimumSystem: minimumSystem)
        let system = OperatingSystemVersion(majorVersion: macOS, minorVersion: 6, patchVersion: 0)
        #expect(stored.stillUnsupported(current: current, system: system) == (unsupported ? stored : nil))
    }

    /// Stored as builds since 1.2.0 wrote it: the version as a plain "1.2.0" string. One whose version
    /// can't be read doesn't load (`PreferencesTests` checks it loads as none).
    @Test func anUnsupportedUpdateIsStoredWithItsVersionAsAString() throws {
        let stored = Data(#"{"version":"1.2.0","minimumSystem":"15.0"}"#.utf8)
        let decoded = try JSONDecoder().decode(UnsupportedUpdate.self, from: stored)
        #expect(decoded == UnsupportedUpdate(version: AppVersion(major: 1, minor: 2, patch: 0), minimumSystem: "15.0"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(decoded), as: UTF8.self) == #"{"minimumSystem":"15.0","version":"1.2.0"}"#)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UnsupportedUpdate.self, from: Data(#"{"version":"1.2","minimumSystem":"15.0"}"#.utf8))
        }
    }

    // MARK: Install state

    /// From Install until the copy is ready, and from Install and Relaunch on, nothing changes the offer. The
    /// other states, after a check: a changed offer starts again from Install; the same offer keeps a ready
    /// or revealed copy, and gets Install back after a failure.
    @Test(arguments: [
        (.idle, false, .idle, .idle),
        (.downloading(0.5), true, nil, nil),
        (.verifying, true, nil, nil),
        (.ready, false, .idle, .ready),
        (.installing, true, nil, nil),
        (.revealed(revealedCopy), false, .idle, .revealed(revealedCopy)),
        (.failed(.download), false, .idle, .idle),
    ] as [(UpdateInstallState, Bool, UpdateInstallState?, UpdateInstallState?)])
    func installState(_ state: UpdateInstallState, isInProgress: Bool, afterChangedOffer: UpdateInstallState?, afterSameOffer: UpdateInstallState?) {
        #expect(state.isInProgress == isInProgress)
        if let afterChangedOffer, let afterSameOffer {
            #expect(state.afterCheck(offerChanged: true) == afterChangedOffer)
            #expect(state.afterCheck(offerChanged: false) == afterSameOffer)
        }
    }

    static let revealedCopy = URL(fileURLWithPath: "/tmp/Join 1.1.0/Join.app")

    // MARK: After a check

    /// Join! 1.`minor`.0.
    static func update(_ minor: Int) -> AvailableUpdate {
        let version = AppVersion(major: 1, minor: minor, patch: 0)
        return AvailableUpdate(
            version: version,
            pageURL: UpdateCheck.releasesPageURL.appending(components: "tag", version.tag),
            downloadURL: UpdateCheck.releasesPageURL.appending(components: "download", version.tag, UpdateCheck.assetName),
            digest: .missing,
            size: 2_486_395
        )
    }

    /// What a check found, where the offer stood, and what the check makes of it (`UpdateChecker`).
    struct Check: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let found: AvailableUpdate?
        /// The release this Mac can't run, which needs macOS 15.0.
        let unsupported: UnsupportedUpdate?
        let offeredUpdate: AvailableUpdate?
        let install: UpdateInstallState
        let outcome: UpdateCheckOutcome

        init(
            _ name: String,
            found: AvailableUpdate?,
            unsupported: AppVersion? = nil,
            offered offeredUpdate: AvailableUpdate?,
            install: UpdateInstallState = .idle,
            _ outcome: UpdateCheckOutcome
        ) {
            testDescription = name
            self.found = found
            self.unsupported = unsupported.map { UnsupportedUpdate(version: $0, minimumSystem: "15.0") }
            self.offeredUpdate = offeredUpdate
            self.install = install
            self.outcome = outcome
        }
    }

    static let checks: [Check] = [
        Check("1.1.0 found", found: update(1), offered: nil, UpdateCheckOutcome(
            status: .available(update(1)), offeredUpdate: update(1), install: .idle, discardsDownload: true
        )),
        Check("up to date", found: nil, offered: nil, UpdateCheckOutcome(
            status: .upToDate, offeredUpdate: nil, install: .idle, discardsDownload: false
        )),
        Check("the same release keeps a ready copy", found: update(1), offered: update(1), install: .ready, UpdateCheckOutcome(
            status: .available(update(1)), offeredUpdate: update(1), install: .ready, discardsDownload: false
        )),
        Check("the same release gets Install back after a failure", found: update(1), offered: update(1), install: .failed(.checksum),
              UpdateCheckOutcome(
                  status: .available(update(1)), offeredUpdate: update(1), install: .idle, discardsDownload: false
              )),
        Check("a newer release discards a ready copy", found: update(2), offered: update(1), install: .ready, UpdateCheckOutcome(
            status: .available(update(2)), offeredUpdate: update(2), install: .idle, discardsDownload: true
        )),
        Check("the release is gone, and so is the ready copy", found: nil, offered: update(1), install: .ready, UpdateCheckOutcome(
            status: .upToDate, offeredUpdate: nil, install: .idle, discardsDownload: true
        )),
        // Checks that were under way when Install, or Install and Relaunch, was clicked.
        Check("a download under way keeps its update", found: update(2), offered: update(1), install: .downloading(0.5),
              UpdateCheckOutcome(
                  status: .available(update(2)), offeredUpdate: update(1), install: .downloading(0.5), discardsDownload: false
              )),
        Check("an install under way keeps its update", found: nil, offered: update(1), install: .installing, UpdateCheckOutcome(
            status: .upToDate, offeredUpdate: update(1), install: .installing, discardsDownload: false
        )),
        Check("the release this Mac can't run isn't offered again", found: update(2), unsupported: update(2).version, offered: nil,
              UpdateCheckOutcome(
                  status: .unsupported(UnsupportedUpdate(version: update(2).version, minimumSystem: "15.0")), offeredUpdate: nil,
                  install: .idle, discardsDownload: false
              )),
        Check("a newer release than the one this Mac can't run", found: update(3), unsupported: update(2).version, offered: nil,
              UpdateCheckOutcome(
                  status: .available(update(3)), offeredUpdate: update(3), install: .idle, discardsDownload: true
              )),
        Check("up to date after a release this Mac can't run", found: nil, unsupported: update(2).version, offered: nil,
              UpdateCheckOutcome(
                  status: .upToDate, offeredUpdate: nil, install: .idle, discardsDownload: false
              )),
    ]

    /// The offer, whose version is remembered, and whether the stored release this Mac can't run is
    /// forgotten follow from the status: only an available update is offered, and only finding the release
    /// this Mac can't run again keeps it.
    @Test(arguments: [
        ("an update", update(1), nil, update(1), true),
        ("up to date", nil, update(2).version, nil, true),
        ("the release this Mac can't run", update(2), update(2).version, nil, false),
        ("a newer release than the one this Mac can't run", update(3), update(2).version, update(3), true),
    ] as [(String, AvailableUpdate?, AppVersion?, AvailableUpdate?, Bool)])
    func theOfferAndTheUnsupportedReleaseFollowTheStatus(
        _ name: String, found: AvailableUpdate?, unsupported: AppVersion?, offer: AvailableUpdate?, forgetsUnsupported: Bool
    ) {
        let unsupported = unsupported.map { UnsupportedUpdate(version: $0, minimumSystem: "15.0") }
        let outcome = UpdateCheckOutcome(found: found, unsupported: unsupported, offeredUpdate: nil, install: .idle)
        #expect(outcome.offer == offer)
        #expect(outcome.forgetsUnsupported == forgetsUnsupported)
    }

    @Test(arguments: checks)
    func afterACheck(_ check: Check) {
        let outcome = UpdateCheckOutcome(found: check.found, unsupported: check.unsupported, offeredUpdate: check.offeredUpdate, install: check.install)
        #expect(outcome == check.outcome)
    }
}
