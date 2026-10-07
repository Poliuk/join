import Foundation
import JoinCore

/// Where the update check finds the latest release.
protocol ReleaseFeed: Sendable {
    func latestRelease() async throws -> GitHubRelease
}

/// GitHub's latest release, asked for without a token: one GET that sends nothing but the headers below.
struct GitHubReleaseFeed: ReleaseFeed {
    /// "Join/1.0.0". GitHub refuses requests without a User-Agent.
    let userAgent: String

    init(current: AppVersion) {
        userAgent = Self.userAgent(current)
    }

    static func userAgent(_ version: AppVersion) -> String {
        "Join/\(version)"
    }

    func latestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: UpdateCheck.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // A fixed language, so the request doesn't carry the user's.
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Anything but 200 (a 403 or 429 rate limit, a 5xx) is a failed check, retried no sooner than an hour.
        guard status == 200 else { throw ReleaseFeedError.status(status) }
        return try UpdateCheck.decodeRelease(data)
    }

    private static let session = URLSession(configuration: .updates(total: 20))
}

enum ReleaseFeedError: Error {
    case status(Int)
}

extension URLSessionConfiguration {
    /// Ephemeral, with no cookies, cache or stored credentials, so every update request stands alone.
    /// A request gives up after 20 s without data, or after `total` seconds in all.
    static func updates(total: TimeInterval) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = min(total, 20)
        configuration.timeoutIntervalForResource = total
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return configuration
    }
}

/// The update check in a fixture run, picked with JOIN_FIXTURE_UPDATE: `current` (the default) finds the
/// running version, `available` a release one minor version above it with a Join.zip, and `failed` can't
/// be reached. `live` asks GitHub instead and lets Install really install, for end-to-end tests only;
/// otherwise a fixture run never touches the network.
struct FixtureReleaseFeed: ReleaseFeed {
    static let environmentKey = "JOIN_FIXTURE_UPDATE"

    enum Mode: String, CaseIterable {
        case current
        case available
        case failed
        case live
    }

    /// An unknown value reads as `current`, so a typo can't turn on real installs.
    static var mode: Mode {
        guard let value = ProcessInfo.processInfo.environment[environmentKey], !value.isEmpty else { return .current }
        guard let mode = Mode(rawValue: value) else {
            NSLog("Join: ignoring unknown %@=%@; known modes: %@", environmentKey, value,
                  Mode.allCases.map(\.rawValue).joined(separator: ", "))
            return .current
        }
        return mode
    }

    let mode: Mode
    let current: AppVersion

    func latestRelease() async throws -> GitHubRelease {
        // Long enough to see "Checking…".
        try await Task.sleep(for: .seconds(1))
        let asset = GitHubRelease.Asset(name: UpdateCheck.assetName, size: 2_500_000)
        switch mode {
        case .available:
            let next = AppVersion(major: current.major, minor: current.minor + 1, patch: 0)
            return GitHubRelease(tagName: next.tag, assets: [asset])
        case .failed:
            throw URLError(.notConnectedToInternet)
        case .current, .live:
            return GitHubRelease(tagName: current.tag, assets: [asset])
        }
    }
}
