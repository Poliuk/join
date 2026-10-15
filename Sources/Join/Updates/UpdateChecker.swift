import AppKit
import Observation
import OSLog
import JoinCore

private let logger = Logger(subsystem: "com.poliuk.join", category: "updates")

/// Asks for a newer release once a day, or when Check Now is clicked, and installs it when asked, in two
/// steps: Install downloads and verifies the new copy, which then waits, ready, and only Install and
/// Relaunch replaces the app and quits. One check runs at a time, and both buttons wait for it. What a
/// successful check found is stored in preferences; a failed one is only remembered here, so the next
/// automatic check waits an hour, and only Settings mentions it.
@Observable
final class UpdateChecker {
    private(set) var status: UpdateStatus = .unknown
    private(set) var install: UpdateInstallState = .idle
    /// The update on offer: found by the last check that found one, and kept through later checks that
    /// fail, while it installs and while it's ready. The panel's update bar shows while there is one.
    private(set) var offeredUpdate: AvailableUpdate?
    /// The running app's version. nil in a build without one (`swift run`), which never checks.
    let currentVersion: AppVersion?
    /// False in a fixture run, unless JOIN_FIXTURE_UPDATE is live or ready.
    let canInstall: Bool

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let feed: any ReleaseFeed
    /// The fixture scenario (JOIN_FIXTURE) this run uses, if any.
    @ObservationIgnored private let fixtureScenario: String?
    @ObservationIgnored private var lastFailure: Date?
    /// The install from Install on, downloading, ready or putting the copy in place, so its download can
    /// be discarded. nil once it has ended.
    @ObservationIgnored private var installer: (any UpdateInstalling)?
    /// JOIN_FIXTURE_UPDATE=ready: Install goes through `FixtureUpdateInstaller`.
    @ObservationIgnored private let simulatesInstall: Bool
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
        simulatesInstall = fixtureMode == .ready
        canInstall = !usesFixtureFeed || simulatesInstall
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

    /// From Install until the copy is ready, and from Install and Relaunch on (`isInProgress`). Not while
    /// ready: a check may then run, and a newer release takes the ready one's place.
    var isInstalling: Bool { install.isInProgress }

    /// At launch: when the last check offered an update newer than this copy, checks again straight away,
    /// so the offer comes back (as the release stands now) without waiting a day. Until that check
    /// succeeds there's no offer to show; if it fails, it's retried an hour later like any failed check.
    /// Otherwise checks if the daily check is due. Also clears what installs left behind when Join! crashed.
    func start(now: Date) {
        if canInstall, !simulatesInstall {
            Task.detached(priority: .utility) { UpdateInstaller.removeLeftovers() }
        }
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
        let offerChanged = update != offeredUpdate
        // A newer release, or none any more: a copy downloaded for the old offer goes.
        if offerChanged { discardDownload() }
        install = install.afterCheck(offerChanged: offerChanged)
        offeredUpdate = update
    }

    /// Install: downloads and verifies the offered update, which then waits, ready, for Install and
    /// Relaunch. Nothing is replaced and nothing quits. Not while a check runs, which may change the offer.
    func installUpdate() {
        guard canInstall, let update = offeredUpdate, let currentVersion, !isChecking, !isInstalling else { return }
        switch install {
        case .idle, .failed: break
        case .downloading, .verifying, .ready, .installing, .revealed: return
        }
        let installer: any UpdateInstalling
        do {
            installer = try makeInstaller(for: update, currentVersion: currentVersion)
        } catch {
            installFailed(update, error: error)
            return
        }
        self.installer = installer
        install = .downloading(nil)
        Task {
            do {
                try await installer.prepare { state in
                    Task { @MainActor in self.installProgressed(state) }
                }
                logger.notice("Downloaded and verified \(update.version.description, privacy: .public); ready to install")
                install = .ready
            } catch {
                // A failed download leaves nothing behind.
                self.installer = nil
                installFailed(update, error: error)
            }
        }
    }

    /// Install and Relaunch: puts the ready copy in place, then quits so the helper can open it; or
    /// reveals it in Finder when it can't replace the running one. Not while a check runs, which may
    /// replace the offer.
    func installAndRelaunch() {
        guard case .ready = install, let installer, let update = offeredUpdate, !isChecking else { return }
        guard installer.hasReadyCopy else {
            // Removed behind Join!'s back, or some of its files: Install downloads it again.
            logger.error("The downloaded copy of \(update.version.description, privacy: .public) is gone; offering Install again")
            discardDownload()
            install = .idle
            return
        }
        install = .installing
        Task {
            do {
                let outcome = try await installer.install()
                self.installer = nil
                switch outcome {
                case .relaunching:
                    logger.notice("Installed \(update.version.description, privacy: .public); relaunching")
                    NSApp.terminate(nil)
                case .revealed(let app):
                    logger.notice("Couldn't replace the running copy; revealed \(update.version.description, privacy: .public) instead")
                    install = .revealed(app)
                    NSWorkspace.shared.activateFileViewerSelecting([app])
                }
            } catch let damaged as ReadyCopyDamaged {
                // Damaged while it waited and removed by `install`, with nothing replaced: like a copy that's
                // gone, Install downloads it again. `discardDownload()` does nothing while installing.
                logger.error("The downloaded copy of \(update.version.description, privacy: .public) no longer passes its checks (\(String(describing: damaged.reason), privacy: .public)); offering Install again")
                self.installer = nil
                install = .idle
            } catch {
                // `install` leaves nothing of the download behind, however it ends.
                self.installer = nil
                installFailed(update, error: error)
            }
        }
    }

    /// Removes the download, under way or ready, so nothing is left of an update that wasn't installed:
    /// when the offer changes, and when Join! quits without Install and Relaunch (the next launch offers
    /// the update again, to be downloaded again). Not once Install and Relaunch is putting the copy in
    /// place: that step removes the folder itself when it ends, and removing it under the swap could put a
    /// partly deleted copy in place.
    func discardDownload() {
        if case .installing = install { return }
        installer?.discard()
        installer = nil
    }

    private func makeInstaller(for update: AvailableUpdate, currentVersion: AppVersion) throws -> any UpdateInstalling {
        if simulatesInstall {
            return FixtureUpdateInstaller(relaunchEnvironment: relaunchEnvironment)
        }
        return try UpdateInstaller(
            update: update,
            revealFolder: revealFolder,
            relaunchEnvironment: relaunchEnvironment,
            userAgent: GitHubReleaseFeed.userAgent(currentVersion)
        )
    }

    private func installFailed(_ update: AvailableUpdate, error: Error) {
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

    /// Show in Finder after the user has moved the revealed copy away: there's nothing left to show, so
    /// the offer goes back to Install.
    func forgetRevealedCopy() {
        guard case .revealed = install else { return }
        install = .idle
    }

    /// Progress (and then `.verifying`) hops here in tasks of its own, so a late one may arrive after the
    /// next step has begun.
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
