import Foundation

/// The part of GitHub's "latest release" response the update check reads.
public struct GitHubRelease: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let size: Int
        /// "sha256:<hex>", or nil for assets uploaded before GitHub started computing digests.
        public let digest: String?

        public init(name: String, size: Int, digest: String? = nil) {
            self.name = name
            self.size = size
            self.digest = digest
        }
    }

    public let tagName: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    public init(tagName: String, draft: Bool = false, prerelease: Bool = false, assets: [Asset]) {
        self.tagName = tagName
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }
}

/// A newer release, with the URLs built from its validated tag rather than taken from the response.
public struct AvailableUpdate: Equatable, Sendable {
    public let version: AppVersion
    /// https://github.com/Poliuk/join/releases/tag/vX.Y.Z
    public let pageURL: URL
    /// https://github.com/Poliuk/join/releases/download/vX.Y.Z/Join.zip
    public let downloadURL: URL
    /// The asset's digest, which gives the download's expected SHA-256.
    public let digest: Digest
    /// In bytes, as GitHub reports it.
    public let size: Int

    public init(version: AppVersion, pageURL: URL, downloadURL: URL, digest: Digest, size: Int) {
        self.version = version
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.digest = digest
        self.size = size
    }

    /// What the release says the download's SHA-256 is. Only `sha256` gives a checksum; without one the
    /// install still checks the app's signature.
    public enum Digest: Equatable, Sendable {
        /// The asset has none: uploaded before GitHub started computing digests.
        case missing
        /// Lowercase hex, from "sha256:<64 hex digits>" in either case.
        case sha256(String)
        /// One that isn't "sha256:<64 hex digits>", as GitHub sent it.
        case unreadable(String)

        /// From the asset's `digest` field.
        init(_ digest: String?) {
            guard let digest else {
                self = .missing
                return
            }
            let prefix = "sha256:"
            let hex = digest.dropFirst(prefix.count).lowercased()
            guard digest.hasPrefix(prefix), hex.utf8.count == 64, hex.utf8.allSatisfy(Self.isHexDigit) else {
                self = .unreadable(digest)
                return
            }
            self = .sha256(hex)
        }

        private static func isHexDigit(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }
}

/// Deciding whether a GitHub release is an update, and when to ask for one.
public enum UpdateCheck {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/Poliuk/join/releases/latest")!
    public static let releasesPageURL = URL(string: "https://github.com/Poliuk/join/releases")!
    public static let assetName = "Join.zip"
    public static let checkInterval: TimeInterval = 24 * 60 * 60
    /// After a failed check, the next one waits at least this long.
    public static let retryInterval: TimeInterval = 60 * 60
    /// In bytes. A bigger Join.zip is refused.
    public static let maximumDownloadSize = 100 * 1024 * 1024

    public static func decodeRelease(_ data: Data) throws -> GitHubRelease {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// nil when the release isn't newer than `current`, is a draft or a prerelease, its tag isn't exactly
    /// "vX.Y.Z", or it has no Join.zip asset of a size between 1 byte and `maximumDownloadSize`.
    public static func update(current: AppVersion, release: GitHubRelease) -> AvailableUpdate? {
        guard !release.draft, !release.prerelease,
              let version = AppVersion(release.tagName), version.tag == release.tagName,
              version > current,
              let asset = release.assets.first(where: { $0.name == assetName }),
              (1...maximumDownloadSize).contains(asset.size)
        else { return nil }
        return AvailableUpdate(
            version: version,
            pageURL: releasesPageURL.appending(components: "tag", version.tag),
            downloadURL: releasesPageURL.appending(components: "download", version.tag, assetName),
            digest: AvailableUpdate.Digest(asset.digest),
            size: asset.size
        )
    }

    /// Due when enabled and never checked, or the last success is at least `checkInterval` ago (or in the
    /// future: the clock moved back), and no check failed within `retryInterval`.
    public static func isDue(enabled: Bool, lastSuccess: Date?, lastFailure: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        if let lastFailure {
            let sinceFailure = now.timeIntervalSince(lastFailure)
            if sinceFailure >= 0, sinceFailure < retryInterval { return false }
        }
        guard let lastSuccess else { return true }
        let sinceSuccess = now.timeIntervalSince(lastSuccess)
        return sinceSuccess < 0 || sinceSuccess >= checkInterval
    }

    /// At launch, whether to check at once, due or not: automatic checks are on and the last successful
    /// check offered `offeredVersion`, newer than `current`, so the offer comes back without waiting a
    /// day. Until that check succeeds, `isDue` is asked as if there had been no success, so a failure is
    /// retried after `retryInterval` rather than at the next daily check.
    public static func rechecksAtLaunch(enabled: Bool, offeredVersion: AppVersion?, current: AppVersion) -> Bool {
        guard enabled, let offeredVersion else { return false }
        return offeredVersion > current
    }

    /// Whether macOS `system` is `minimum` or later, an app's `LSMinimumSystemVersion`: "15.0", "26" or
    /// "14.2.1". One that can't be read doesn't stop an install, so it counts as met.
    public static func system(_ system: OperatingSystemVersion, isAtLeast minimum: String) -> Bool {
        let parts = minimum.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return true }
        let numbers = parts.compactMap { $0 } + [0, 0]
        return (system.majorVersion, system.minorVersion, system.patchVersion) >= (numbers[0], numbers[1], numbers[2])
    }
}

/// A release whose install stopped because it needs a newer macOS ("15.0") than this Mac runs. It isn't
/// offered again; a newer release replaces it. Stored as JSON, {"version":"1.2.0","minimumSystem":"15.0"}:
/// one whose version can't be read doesn't load.
public struct UnsupportedUpdate: Codable, Equatable, Sendable {
    public let version: AppVersion
    /// The new copy's `LSMinimumSystemVersion`, "15.0".
    public let minimumSystem: String

    public init(version: AppVersion, minimumSystem: String) {
        self.version = version
        self.minimumSystem = minimumSystem
    }

    /// This release, while this Mac still can't run it: it's newer than `current`, and macOS `system` is
    /// older than it needs. nil once either has been updated.
    public func stillUnsupported(current: AppVersion, system: OperatingSystemVersion) -> UnsupportedUpdate? {
        guard version > current, !UpdateCheck.system(system, isAtLeast: minimumSystem) else { return nil }
        return self
    }
}

/// What a successful check changes (`UpdateChecker`), from what it found and where the offer stands.
///
/// A release this Mac can't run isn't offered again while checks keep finding it; anything else the check
/// finds forgets it. An install in progress carries on with its own update. Otherwise the update found
/// becomes the offer, and when that changes (a newer release, or none any more) the download made for the
/// old one goes and the bar starts again from Install (`UpdateInstallState.afterCheck(offerChanged:)`).
public struct UpdateCheckOutcome: Equatable, Sendable {
    /// What Settings says: the update found, up to date, or the release this Mac can't run.
    public let status: UpdateStatus
    /// The update on offer from now on, which the update bar shows and Install installs: `offer`, unless
    /// an install in progress keeps its own.
    public let offeredUpdate: AvailableUpdate?
    public let install: UpdateInstallState
    /// The download made for the previous offer goes: the offer changed.
    public let discardsDownload: Bool

    /// The update this check offers: the one found, unless it's the release this Mac can't run. Its version
    /// is remembered, so a relaunch checks again at once and brings the offer back (`rechecksAtLaunch`).
    public var offer: AvailableUpdate? {
        if case .available(let update) = status { update } else { nil }
    }

    /// The release found unsupported earlier is forgotten: the check found something else.
    public var forgetsUnsupported: Bool {
        if case .unsupported = status { false } else { true }
    }
}

extension UpdateCheckOutcome {
    /// - Parameters:
    ///   - found: what the check found (`UpdateCheck.update(current:release:)`).
    ///   - unsupported: the release an earlier install found this Mac can't run, while it still can't
    ///     (`UnsupportedUpdate.stillUnsupported(current:system:)`).
    ///   - offeredUpdate: the update on offer before the check.
    ///   - install: where installing it has got to.
    public init(
        found: AvailableUpdate?,
        unsupported: UnsupportedUpdate?,
        offeredUpdate: AvailableUpdate?,
        install: UpdateInstallState
    ) {
        // The same as the computed `offer`, which can't be read before every stored property is set.
        let offer: AvailableUpdate?
        if let found, let unsupported, found.version == unsupported.version {
            status = .unsupported(unsupported)
            offer = nil
        } else {
            status = found.map(UpdateStatus.available) ?? .upToDate
            offer = found
        }
        if install.isInProgress {
            self.offeredUpdate = offeredUpdate
            self.install = install
            discardsDownload = false
        } else {
            let offerChanged = offer != offeredUpdate
            self.offeredUpdate = offer
            self.install = install.afterCheck(offerChanged: offerChanged)
            discardsDownload = offerChanged
        }
    }
}

/// What the last update check found.
public enum UpdateStatus: Equatable, Sendable {
    case unknown
    case checking
    case upToDate
    case available(AvailableUpdate)
    /// A newer release that needs a newer macOS than this Mac runs. Not an offer: there's nothing to install.
    case unsupported(UnsupportedUpdate)
    case failed
}

/// Why installing an update stopped. `UpdateCopy.failureReason` has the words for the user.
public enum UpdateFailure: Error, Equatable, Sendable {
    case download
    /// Larger than `UpdateCheck.maximumDownloadSize`.
    case tooLarge
    /// The download's SHA-256 isn't the release's digest.
    case checksum
    case unzip
    /// What was unzipped isn't Join! at the update's version.
    case notJoin
    /// The app has no code for this Mac's processor.
    case wrongArchitecture
    /// The app's `LSMinimumSystemVersion`, "15.0", is newer than the running macOS.
    case unsupportedSystem(String)
    case signature
    /// The new copy couldn't be moved where it goes.
    case save
    case relaunch
}

/// Where installing an available update has got to. Install downloads and verifies the new copy, which
/// then waits, `ready`, until Install and Relaunch puts it in place: nothing quits before that click.
public enum UpdateInstallState: Equatable, Sendable {
    case idle
    /// The fraction downloaded, or nil while the size is unknown.
    case downloading(Double?)
    /// Downloaded: checking the archive and the app in it.
    case verifying
    /// Downloaded and verified, waiting for Install and Relaunch.
    case ready
    /// Install and Relaunch was clicked: checking the copy again and putting it in place.
    case installing
    /// Couldn't replace the running copy: the new one waits here for the user to move to Applications.
    case revealed(URL)
    case failed(UpdateFailure)

    /// From Install until the copy is ready, and from Install and Relaunch on: no check starts meanwhile,
    /// and the offer stays as it is. Not while ready, which can last: checks go on, and a newer release
    /// takes the ready one's place.
    public var isInProgress: Bool {
        switch self {
        case .downloading, .verifying, .installing: return true
        case .idle, .ready, .revealed, .failed: return false
        }
    }

    /// What an install that isn't in progress becomes after a successful check. An offer that changed (a
    /// newer release, or none any more) starts again from Install, so a ready copy of the old one is
    /// dropped; the same offer keeps a ready or revealed copy, and gets Install back after a failure.
    public func afterCheck(offerChanged: Bool) -> UpdateInstallState {
        if offerChanged { return .idle }
        if case .failed = self { return .idle }
        return self
    }
}
