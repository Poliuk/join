import AppKit
import Observation
import OSLog
import JoinCore

private let logger = Logger(subsystem: "com.poliuk.join", category: "updates")

/// Asks for a newer release once a day, or when Check Now is clicked, and installs it when asked. One
/// check runs at a time, and Install waits for it. What a successful check found is stored in
/// preferences; a failed one is only remembered here, so the next automatic check waits an hour, and only
/// Settings mentions it.
@MainActor
@Observable
final class UpdateChecker {
    private(set) var status: UpdateStatus = .unknown
    private(set) var install: UpdateInstallState = .idle
    /// The update on offer: found by the last check that found one, and kept through later checks that
    /// fail and while it installs. The panel's update bar shows while there is one.
    private(set) var offeredUpdate: AvailableUpdate?
    /// The running app's version. nil in a build without one (`swift run`), which never checks.
    let currentVersion: AppVersion?
    /// False in a fixture run, unless JOIN_FIXTURE_UPDATE=live.
    let canInstall: Bool

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let feed: any ReleaseFeed
    /// The fixture scenario (JOIN_FIXTURE) this run uses, if any.
    @ObservationIgnored private let fixtureScenario: String?
    @ObservationIgnored private var lastFailure: Date?
    /// Set while the launch re-check of a remembered offer hasn't succeeded yet, so a failure is retried
    /// within the hour rather than at the next daily check.
    @ObservationIgnored private var recheckingOffer = false
    /// True in a fixture run with a fixture feed, which keeps what its checks find in the properties below
    /// instead of the fixture defaults, so every fixture launch checks once and JOIN_FIXTURE_UPDATE decides
    /// what it finds.
    @ObservationIgnored private let keepsChecksInMemory: Bool
    private var lastCheckInMemory: Date?
    @ObservationIgnored private var offeredVersionInMemory: String?
    @ObservationIgnored private var unsupportedUpdateInMemory: UnsupportedUpdate?

    init(preferences: Preferences, fixtureScenario: String?) {
        let current = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
        let version = current ?? AppVersion(major: 0, minor: 0, patch: 0)
        let fixtureMode = fixtureScenario.map { _ in FixtureReleaseFeed.mode }
        let usesFixtureFeed = fixtureMode.map { $0 != .live } ?? false
        self.preferences = preferences
        self.fixtureScenario = fixtureScenario
        currentVersion = current
        canInstall = !usesFixtureFeed
        keepsChecksInMemory = usesFixtureFeed
        if let fixtureMode, usesFixtureFeed {
            feed = FixtureReleaseFeed(mode: fixtureMode, current: version)
        } else {
            feed = GitHubReleaseFeed(current: version)
        }
        // A release an earlier run found this Mac can't run reads as such until the next check.
        if let unsupported = stillUnsupported {
            status = .unsupported(unsupported.version, minimumSystem: unsupported.minimumSystem)
        }
    }

    /// When the last check succeeded.
    private(set) var lastCheck: Date? {
        get { keepsChecksInMemory ? lastCheckInMemory : preferences.lastUpdateCheck }
        set {
            if keepsChecksInMemory { lastCheckInMemory = newValue } else { preferences.lastUpdateCheck = newValue }
        }
    }

    /// The version the last successful check offered, so a relaunch can bring the offer back.
    private var offeredVersion: String? {
        get { keepsChecksInMemory ? offeredVersionInMemory : preferences.offeredUpdateVersion }
        set {
            if keepsChecksInMemory { offeredVersionInMemory = newValue } else { preferences.offeredUpdateVersion = newValue }
        }
    }

    /// A release whose install found it needs a newer macOS. Kept while checks keep finding it, and not
    /// offered meanwhile.
    private var unsupportedUpdate: UnsupportedUpdate? {
        get { keepsChecksInMemory ? unsupportedUpdateInMemory : preferences.unsupportedUpdate }
        set {
            if keepsChecksInMemory { unsupportedUpdateInMemory = newValue } else { preferences.unsupportedUpdate = newValue }
        }
    }

    /// `unsupportedUpdate`, while it's newer than this copy and this Mac's macOS is still too old for it.
    private var stillUnsupported: (version: AppVersion, minimumSystem: String)? {
        guard let unsupportedUpdate, let currentVersion,
              let version = AppVersion(unsupportedUpdate.version), version > currentVersion,
              !UpdateInstaller.systemIsAtLeast(unsupportedUpdate.minimumSystem)
        else { return nil }
        return (version, unsupportedUpdate.minimumSystem)
    }

    var isChecking: Bool { status == .checking }

    var isInstalling: Bool {
        switch install {
        case .downloading, .installing: return true
        case .idle, .revealed, .failed: return false
        }
    }

    /// At launch: when the last check offered an update newer than this copy, checks again straight away,
    /// so the offer comes back (as the release stands now) without waiting a day. Until that check
    /// succeeds there's no offer to show; if it fails, it's retried an hour later like any failed check.
    /// Otherwise checks if the daily check is due.
    func start(now: Date) {
        if preferences.checksForUpdates, let currentVersion,
           let offered = offeredVersion.flatMap(AppVersion.init), offered > currentVersion {
            recheckingOffer = true
            check()
        } else {
            tick(now: now)
        }
    }

    /// Checks if the daily check is due. Called on every half-minute tick and on wake.
    func tick(now: Date) {
        guard UpdateCheck.isDue(
            enabled: preferences.checksForUpdates,
            lastSuccess: recheckingOffer ? nil : lastCheck,
            lastFailure: lastFailure,
            now: now
        ) else { return }
        check()
    }

    /// Settings' Check Now, which works with automatic checks off too.
    func checkNow() {
        check()
    }

    private func check() {
        guard let currentVersion, !isChecking, !isInstalling else { return }
        status = .checking
        Task {
            do {
                let release = try await feed.latestRelease()
                let update = UpdateCheck.update(current: currentVersion, release: release)
                logger.notice("Latest release \(release.tagName, privacy: .public); update: \(update?.version.description ?? "none", privacy: .public)")
                finishCheck(with: update)
            } catch {
                logger.error("Update check failed: \(String(describing: error), privacy: .public)")
                lastFailure = Date()
                status = .failed
            }
        }
    }

    private func finishCheck(with found: AvailableUpdate?) {
        lastCheck = Date()
        lastFailure = nil
        recheckingOffer = false
        // A release this Mac can't run isn't offered again. Any other result (a newer release, say)
        // forgets it.
        var update = found
        if let found, let unsupported = stillUnsupported, found.version == unsupported.version {
            status = .unsupported(unsupported.version, minimumSystem: unsupported.minimumSystem)
            update = nil
        } else {
            unsupportedUpdate = nil
            status = found.map(UpdateStatus.available) ?? .upToDate
        }
        offeredVersion = update?.version.description
        // An install under way carries on with the update it started with.
        guard !isInstalling else { return }
        if update != offeredUpdate {
            install = .idle
        } else if case .failed = install {
            // The same update again: offer Install again.
            install = .idle
        }
        offeredUpdate = update
    }

    /// Downloads and installs the offered update, then quits so the helper can open the new copy; or
    /// reveals it in Finder when it can't replace the running one. Not while a check runs, which may
    /// change the offer.
    func installUpdate() {
        guard canInstall, let update = offeredUpdate, let currentVersion, !isChecking, !isInstalling else { return }
        if case .revealed = install { return }
        install = .downloading(nil)
        let installer = UpdateInstaller(
            update: update,
            revealFolder: revealFolder,
            relaunchEnvironment: relaunchEnvironment,
            userAgent: GitHubReleaseFeed.userAgent(currentVersion)
        )
        Task {
            do {
                let outcome = try await installer.run { [weak self] state in
                    Task { @MainActor [weak self] in self?.installProgressed(state) }
                }
                switch outcome {
                case .relaunching:
                    logger.notice("Installed \(update.version.description, privacy: .public); relaunching")
                    NSApp.terminate(nil)
                case .revealed(let app):
                    logger.notice("Couldn't replace the running copy; revealed \(update.version.description, privacy: .public) instead")
                    install = .revealed(app)
                    NSWorkspace.shared.activateFileViewerSelecting([app])
                }
            } catch {
                logger.error("Install failed: \(String(describing: error), privacy: .public)")
                let failure = error as? UpdateFailure ?? .download
                if case .unsupportedSystem(let minimum) = failure {
                    // Not an offer any more: the bar goes, and Settings says which macOS it needs.
                    unsupportedUpdate = UnsupportedUpdate(version: update.version.description, minimumSystem: minimum)
                    offeredVersion = nil
                    status = .unsupported(update.version, minimumSystem: minimum)
                    offeredUpdate = nil
                    install = .idle
                } else {
                    install = .failed(failure)
                }
            }
        }
    }

    /// Show in Finder after the user has moved the revealed copy away: there's nothing left to show, so
    /// the offer goes back to Install.
    func forgetRevealedCopy() {
        guard case .revealed = install else { return }
        install = .idle
    }

    /// Progress hops here in tasks of its own, so a late one may arrive after the next step has begun.
    private func installProgressed(_ state: UpdateInstallState) {
        guard case .downloading = install else { return }
        install = state
    }

    /// ~/Downloads, or a temporary folder in fixture runs, which never touch the user's files.
    private var revealFolder: URL {
        if fixtureScenario != nil {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("JoinUpdate", isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// A fixture run relaunches as the same fixture.
    private var relaunchEnvironment: [String: String] {
        guard let fixtureScenario else { return [:] }
        var environment = [FixtureCalendarService.environmentKey: fixtureScenario]
        environment[FixtureReleaseFeed.environmentKey] = ProcessInfo.processInfo.environment[FixtureReleaseFeed.environmentKey]
        return environment
    }
}
