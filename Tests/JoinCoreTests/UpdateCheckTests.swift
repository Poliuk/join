import XCTest
@testable import JoinCore

final class UpdateCheckTests: XCTestCase {
    private let current = AppVersion(major: 1, minor: 0, patch: 0)
    private let hex = "5b6a8afae5540e126ed053255720da7325c4532d7b802ba7878df823a5deaec7"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Shaped like api.github.com/repos/Poliuk/join/releases/latest, with the keys Join! doesn't read
    /// left in (some trimmed).
    private let latestResponse = """
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

    private func release(
        tag: String = "v1.1.0",
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [GitHubRelease.Asset]? = nil
    ) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            draft: draft,
            prerelease: prerelease,
            assets: assets ?? [GitHubRelease.Asset(name: "Join.zip", size: 2_486_395, digest: "sha256:" + hex)]
        )
    }

    // MARK: Decoding

    func testDecodesTheLatestReleaseResponse() throws {
        let decoded = try UpdateCheck.decodeRelease(Data(latestResponse.utf8))
        XCTAssertEqual(decoded.tagName, "v1.1.0")
        XCTAssertFalse(decoded.draft)
        XCTAssertFalse(decoded.prerelease)
        XCTAssertEqual(decoded.assets, [
            GitHubRelease.Asset(name: "Join.zip", size: 2_486_395, digest: "sha256:" + hex),
            GitHubRelease.Asset(name: "Join.dSYM.zip", size: 1_048_576, digest: nil),
        ])
    }

    func testDecodingRejectsOtherResponses() {
        let responses = [
            "",
            "not json",
            "[]",
            #"{"message": "API rate limit exceeded", "documentation_url": "https://docs.github.com/rest"}"#,
            #"{"tag_name": "v1.1.0", "draft": false, "prerelease": false}"#,
            #"{"tag_name": "v1.1.0", "draft": "no", "prerelease": false, "assets": []}"#,
            #"{"tag_name": "v1.1.0", "draft": false, "prerelease": false, "assets": [{"name": "Join.zip"}]}"#,
        ]
        for response in responses {
            XCTAssertNil(try? UpdateCheck.decodeRelease(Data(response.utf8)), response)
        }
    }

    func testDecodesAnAssetWithoutADigest() throws {
        let json = #"{"tag_name": "v1.1.0", "draft": false, "prerelease": false, "assets": [{"name": "Join.zip", "size": 10}]}"#
        let decoded = try UpdateCheck.decodeRelease(Data(json.utf8))
        XCTAssertEqual(decoded.assets, [GitHubRelease.Asset(name: "Join.zip", size: 10, digest: nil)])
    }

    // MARK: Update

    func testNewerReleaseIsAnUpdateWithURLsBuiltFromTheTag() throws {
        let decoded = try UpdateCheck.decodeRelease(Data(latestResponse.utf8))
        let update = try XCTUnwrap(UpdateCheck.update(current: current, release: decoded))
        XCTAssertEqual(update.version, AppVersion(major: 1, minor: 1, patch: 0))
        XCTAssertEqual(update.pageURL.absoluteString, "https://github.com/Poliuk/join/releases/tag/v1.1.0")
        XCTAssertEqual(update.downloadURL.absoluteString, "https://github.com/Poliuk/join/releases/download/v1.1.0/Join.zip")
        XCTAssertEqual(update.sha256, hex)
        XCTAssertEqual(update.size, 2_486_395)
    }

    func testOnlyANewerVersionIsAnUpdate() {
        XCTAssertNil(UpdateCheck.update(current: current, release: release(tag: "v1.0.0")), "equal")
        XCTAssertNil(UpdateCheck.update(current: current, release: release(tag: "v0.9.9")), "older")
        XCTAssertNotNil(UpdateCheck.update(current: current, release: release(tag: "v1.0.1")))
        XCTAssertNotNil(UpdateCheck.update(current: current, release: release(tag: "v2.0.0")))
        XCTAssertNil(UpdateCheck.update(current: AppVersion(major: 1, minor: 10, patch: 0), release: release(tag: "v1.9.0")))
    }

    func testDraftsAndPrereleasesAreNotUpdates() {
        XCTAssertNil(UpdateCheck.update(current: current, release: release(draft: true)))
        XCTAssertNil(UpdateCheck.update(current: current, release: release(prerelease: true)))
    }

    func testTagMustBeExactlyVMajorMinorPatch() {
        for tag in ["1.1.0", "v1.1", "v1.1.0.1", "v1.1.0-beta", "V1.1.0", "release-1.1.0", "v01.1.0", "v1.1.0/../../evil", ""] {
            XCTAssertNil(UpdateCheck.update(current: current, release: release(tag: tag)), tag)
        }
    }

    func testNeedsAJoinZipAssetOfAnAcceptableSize() {
        XCTAssertNil(UpdateCheck.update(current: current, release: release(assets: [])), "no assets")
        XCTAssertNil(UpdateCheck.update(current: current, release: release(assets: [
            GitHubRelease.Asset(name: "Join-1.1.0.zip", size: 1000, digest: nil),
            GitHubRelease.Asset(name: "join.zip", size: 1000, digest: nil),
        ])), "no asset named exactly Join.zip")
        let oversized = GitHubRelease.Asset(name: "Join.zip", size: UpdateCheck.maximumDownloadSize + 1, digest: nil)
        XCTAssertNil(UpdateCheck.update(current: current, release: release(assets: [oversized])), "oversized")
        let empty = GitHubRelease.Asset(name: "Join.zip", size: 0, digest: nil)
        XCTAssertNil(UpdateCheck.update(current: current, release: release(assets: [empty])), "empty")
        let largest = GitHubRelease.Asset(name: "Join.zip", size: UpdateCheck.maximumDownloadSize, digest: nil)
        XCTAssertEqual(UpdateCheck.update(current: current, release: release(assets: [largest]))?.size, UpdateCheck.maximumDownloadSize)

        let others = GitHubRelease.Asset(name: "Join.dSYM.zip", size: 5000, digest: nil)
        let join = GitHubRelease.Asset(name: "Join.zip", size: 1234, digest: nil)
        XCTAssertEqual(UpdateCheck.update(current: current, release: release(assets: [others, join]))?.size, 1234)
    }

    func testDigestBecomesLowercaseHexOrNil() {
        func sha256(_ digest: String?) -> String?? {
            let asset = GitHubRelease.Asset(name: "Join.zip", size: 1000, digest: digest)
            return UpdateCheck.update(current: current, release: release(assets: [asset])).map(\.sha256)
        }
        XCTAssertEqual(sha256("sha256:" + hex), hex)
        XCTAssertEqual(sha256("sha256:" + hex.uppercased()), hex)
        XCTAssertEqual(sha256(nil), .some(nil), "absent: still an update, without a checksum")
        let short = String(hex.dropLast())
        let malformed: [String] = [
            "", "sha256:", hex, "sha256:" + short, "sha256:" + hex + "0", "sha256:" + short + "g", "sha256: " + short,
            "sha512:" + hex, "SHA256:" + hex, "md5:d41d8cd98f00b204e9800998ecf8427e",
        ]
        for digest in malformed {
            XCTAssertEqual(sha256(digest), .some(nil), digest)
        }
    }

    func testFixedURLsAndLimits() {
        XCTAssertEqual(UpdateCheck.latestReleaseURL.absoluteString, "https://api.github.com/repos/Poliuk/join/releases/latest")
        XCTAssertEqual(UpdateCheck.releasesPageURL.absoluteString, "https://github.com/Poliuk/join/releases")
        XCTAssertEqual(UpdateCheck.assetName, "Join.zip")
        XCTAssertEqual(UpdateCheck.checkInterval, 24 * 60 * 60)
        XCTAssertEqual(UpdateCheck.retryInterval, 60 * 60)
        XCTAssertEqual(UpdateCheck.maximumDownloadSize, 104_857_600)
    }

    // MARK: Schedule

    func testIsDue() {
        func due(enabled: Bool = true, success: TimeInterval?, failure: TimeInterval? = nil) -> Bool {
            UpdateCheck.isDue(
                enabled: enabled,
                lastSuccess: success.map { now.addingTimeInterval(-$0) },
                lastFailure: failure.map { now.addingTimeInterval(-$0) },
                now: now
            )
        }
        let hour: TimeInterval = 60 * 60
        XCTAssertFalse(due(enabled: false, success: nil), "disabled")
        XCTAssertFalse(due(enabled: false, success: 25 * hour), "disabled")
        XCTAssertTrue(due(success: nil), "never checked")
        XCTAssertFalse(due(success: hour), "1 h ago")
        XCTAssertFalse(due(success: 24 * hour - 1), "just under a day ago")
        XCTAssertTrue(due(success: 24 * hour), "a day ago")
        XCTAssertTrue(due(success: 25 * hour), "25 h ago")
        XCTAssertTrue(due(success: -hour), "in the future: the clock moved back")
        XCTAssertFalse(due(success: nil, failure: 10 * 60), "never checked, failed 10 min ago")
        XCTAssertFalse(due(success: 25 * hour, failure: hour - 1), "failed just under an hour ago")
        XCTAssertTrue(due(success: 25 * hour, failure: hour), "failed an hour ago")
        XCTAssertTrue(due(success: nil, failure: 2 * hour), "old failure")
        XCTAssertFalse(due(success: hour, failure: 2 * hour), "old failure, recent success")
        XCTAssertTrue(due(success: nil, failure: -hour), "failure in the future: the clock moved back")
    }

    // MARK: Status

    func testAvailableUpdateComesOnlyFromAvailable() throws {
        let update = try XCTUnwrap(UpdateCheck.update(current: current, release: release()))
        XCTAssertEqual(UpdateStatus.available(update).availableUpdate, update)
        let unsupported = UpdateStatus.unsupported(AppVersion(major: 1, minor: 1, patch: 0), minimumSystem: "15.0")
        for status in [UpdateStatus.unknown, .checking, .upToDate, unsupported, .failed] {
            XCTAssertNil(status.availableUpdate, "\(status)")
        }
    }

    func testUnsupportedUpdateRoundTripsAsJSON() throws {
        let unsupported = UnsupportedUpdate(version: "1.2.0", minimumSystem: "15.0")
        let data = try JSONEncoder().encode(unsupported)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["version": "1.2.0", "minimumSystem": "15.0"])
        XCTAssertEqual(try JSONDecoder().decode(UnsupportedUpdate.self, from: data), unsupported)
    }
}
