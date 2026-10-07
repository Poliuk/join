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
    /// Lowercase hex from the asset's "sha256:<hex>" digest; nil if it has none or it's malformed.
    public let sha256: String?
    /// In bytes, as GitHub reports it.
    public let size: Int

    public init(version: AppVersion, pageURL: URL, downloadURL: URL, sha256: String?, size: Int) {
        self.version = version
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.size = size
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
            sha256: asset.digest.flatMap(sha256(fromDigest:)),
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

    /// "sha256:<64 hex digits>", in either case, to lowercase hex.
    private static func sha256(fromDigest digest: String) -> String? {
        let prefix = "sha256:"
        guard digest.hasPrefix(prefix) else { return nil }
        let hex = digest.dropFirst(prefix.count).lowercased()
        guard hex.utf8.count == 64, hex.utf8.allSatisfy({ isHexDigit($0) }) else { return nil }
        return hex
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
    }
}

/// A release whose install stopped because it needs a newer macOS ("15.0") than this Mac runs. It isn't
/// offered again; a newer release replaces it.
public struct UnsupportedUpdate: Codable, Equatable, Sendable {
    /// "1.2.0".
    public let version: String
    /// The new copy's `LSMinimumSystemVersion`, "15.0".
    public let minimumSystem: String

    public init(version: String, minimumSystem: String) {
        self.version = version
        self.minimumSystem = minimumSystem
    }
}

/// What the last update check found.
public enum UpdateStatus: Equatable, Sendable {
    case unknown
    case checking
    case upToDate
    case available(AvailableUpdate)
    /// A newer release that needs a newer macOS than this Mac runs ("15.0"). Not an offer: there's nothing
    /// to install.
    case unsupported(AppVersion, minimumSystem: String)
    case failed

    public var availableUpdate: AvailableUpdate? {
        if case .available(let update) = self { return update }
        return nil
    }
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

/// Where installing an available update has got to.
public enum UpdateInstallState: Equatable, Sendable {
    case idle
    /// The fraction downloaded, or nil while the size is unknown.
    case downloading(Double?)
    case installing
    /// Couldn't replace the running copy: the new one waits here for the user to move to Applications.
    case revealed(URL)
    case failed(UpdateFailure)
}
