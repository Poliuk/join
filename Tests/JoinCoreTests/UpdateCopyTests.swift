import Foundation
import Testing
@testable import JoinCore

struct UpdateCopyTests {
    static let current = AppVersion(major: 1, minor: 0, patch: 0)
    static let newer = AppVersion(major: 1, minor: 1, patch: 0)
    static let checked = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Join! 1.`minor`.0.
    static func update(_ minor: Int) -> AvailableUpdate {
        let version = AppVersion(major: 1, minor: minor, patch: 0)
        return AvailableUpdate(
            version: version,
            pageURL: URL(string: "https://github.com/Poliuk/join/releases/tag/\(version.tag)")!,
            downloadURL: URL(string: "https://github.com/Poliuk/join/releases/download/\(version.tag)/Join.zip")!,
            sha256: nil,
            size: 2_486_395
        )
    }

    struct Copy: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let actual: String
        let expected: String

        init(_ name: String, _ actual: String, _ expected: String) {
            testDescription = name
            self.actual = actual
            self.expected = expected
        }
    }

    /// Settings › General › Updates. "Check Now" is recorded in the product brief (#10), and "Install and
    /// Relaunch" is the user's choice (2026-10-15).
    @Test(arguments: [
        Copy("section", UpdateCopy.sectionTitle, "Updates"),
        Copy("automatic checks switch", UpdateCopy.automaticChecksTitle, "Check for updates automatically"),
        Copy("Check Now", UpdateCopy.checkNowTitle, "Check Now"),
        Copy("Install", UpdateCopy.installTitle, "Install"),
        Copy("Install and Relaunch", UpdateCopy.installAndRelaunchTitle, "Install and Relaunch"),
    ])
    func settingsCopy(_ copy: Copy) {
        #expect(copy.actual == copy.expected)
    }

    // MARK: Status line

    /// The line beside Check Now, from this copy's version, the check's status, the update on offer and the
    /// last successful check. An offer names the line whatever the status, so Install never sits beside a
    /// line without a version.
    struct StatusLine: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let current: AppVersion?
        let status: UpdateStatus
        let offered: AvailableUpdate?
        let lastCheck: Date?
        let line: String

        init(_ name: String, current: AppVersion? = UpdateCopyTests.current, _ status: UpdateStatus, offered: AvailableUpdate? = nil,
             lastCheck: Date? = nil, _ line: String) {
            testDescription = name
            self.current = current
            self.status = status
            self.offered = offered
            self.lastCheck = lastCheck
            self.line = line
        }
    }

    /// Five minutes before `checked`.
    static let fiveMinutesAgo = checked.addingTimeInterval(-5 * 60)

    @Test(arguments: [
        StatusLine("up to date", .upToDate, lastCheck: fiveMinutesAgo, "Join! 1.0.0 · Checked 5 minutes ago"),
        StatusLine("a check stored by an earlier run", .unknown, lastCheck: fiveMinutesAgo, "Join! 1.0.0 · Checked 5 minutes ago"),
        StatusLine("never checked", .unknown, "Join! 1.0.0"),
        StatusLine("checking", .checking, lastCheck: fiveMinutesAgo, "Join! 1.0.0 · Checking…"),
        StatusLine("failed", .failed, lastCheck: fiveMinutesAgo, "Join! 1.0.0 · Couldn't check for updates"),
        StatusLine("available", .available(update(1)), lastCheck: fiveMinutesAgo, "Join! 1.1.0 is available"),
        StatusLine("unsupported", .unsupported(AppVersion(major: 1, minor: 2, patch: 0), minimumSystem: "15.0"), lastCheck: fiveMinutesAgo,
                   "Join! 1.2.0 needs macOS 15.0 or later"),
        StatusLine("an offer while a check runs", .checking, offered: update(1), "Join! 1.1.0 is available"),
        StatusLine("an offer after a check failed", .failed, offered: update(1), "Join! 1.1.0 is available"),
        StatusLine("an offer from an earlier run", .unknown, offered: update(1), "Join! 1.1.0 is available"),
        StatusLine("an offer beside an older check", .upToDate, offered: update(1), lastCheck: fiveMinutesAgo, "Join! 1.1.0 is available"),
        // The offer is what Install installs.
        StatusLine("an offer beside a newer release found", .available(update(2)), offered: update(1), "Join! 1.1.0 is available"),
        StatusLine("no readable version", current: nil, .unknown, "Join!"),
        StatusLine("no readable version, failed", current: nil, .failed, "Join! · Couldn't check for updates"),
    ])
    func statusLine(_ row: StatusLine) {
        let line = UpdateCopy.statusLine(current: row.current, status: row.status, offered: row.offered, lastCheck: row.lastCheck, now: Self.checked)
        #expect(line == row.line)
    }

    // MARK: Install

    @Test(arguments: [
        (.download, "The download didn't finish."),
        (.tooLarge, "The download is larger than 100 MB."),
        (.checksum, "The download doesn't match the release's checksum."),
        (.unzip, "The download couldn't be unzipped."),
        (.notJoin, "The downloaded app doesn't match the release."),
        (.wrongArchitecture, "This version doesn't run on this Mac's processor."),
        (.unsupportedSystem("15.0"), "This version needs macOS 15.0 or later."),
        (.signature, "The downloaded app's code signature isn't valid."),
        (.save, "The new copy couldn't be saved."),
        (.relaunch, "Join! couldn't reopen itself. Quit it and open it again to finish."),
    ] as [(UpdateFailure, String)])
    func failureReason(_ failure: UpdateFailure, reason: String) {
        #expect(UpdateCopy.failureReason(failure) == reason)
    }

    /// The update bar's message for 1.1.0. "Install 1.1.0" is the user's wording (2026-10-15). The percent is
    /// rounded and kept between 0 and 100, and left out while the size is unknown.
    @Test(arguments: [
        (.idle, "Join! 1.1.0 is available"),
        (.downloading(0.45), "Downloading Join! 1.1.0… 45%"),
        (.downloading(0.294), "Downloading Join! 1.1.0… 29%"),
        (.downloading(0), "Downloading Join! 1.1.0… 0%"),
        (.downloading(1), "Downloading Join! 1.1.0… 100%"),
        (.downloading(1.5), "Downloading Join! 1.1.0… 100%"),
        (.downloading(-0.2), "Downloading Join! 1.1.0… 0%"),
        (.downloading(nil), "Downloading Join! 1.1.0…"),
        (.downloading(.nan), "Downloading Join! 1.1.0…"),
        (.downloading(.infinity), "Downloading Join! 1.1.0…"),
        (.verifying, "Verifying Join! 1.1.0…"),
        (.ready, "Install 1.1.0"),
        (.installing, "Installing Join! 1.1.0…"),
        (.failed(.checksum), "Couldn't install Join! 1.1.0"),
        (.failed(.unsupportedSystem("15.0")), "Couldn't install Join! 1.1.0"),
        (.revealed(URL(fileURLWithPath: "/Users/me/Downloads/Join 1.1.0/Join.app")), "Quit Join!, then move Join! 1.1.0 to Applications"),
    ] as [(UpdateInstallState, String)])
    func barMessage(_ install: UpdateInstallState, message: String) {
        #expect(UpdateCopy.barMessage(version: Self.newer, install: install) == message)
    }

    /// The update bar's button, also in Settings: its title, whether it can be clicked and its tooltip.
    struct BarButton: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let install: UpdateInstallState
        let canInstall: Bool
        let isChecking: Bool
        let title: String?
        let isEnabled: Bool
        let help: String?

        init(_ name: String, _ install: UpdateInstallState, canInstall: Bool = true, isChecking: Bool = false,
             title: String?, isEnabled: Bool, help: String? = nil) {
            testDescription = name
            self.install = install
            self.canInstall = canInstall
            self.isChecking = isChecking
            self.title = title
            self.isEnabled = isEnabled
            self.help = help
        }
    }

    @Test(arguments: [
        BarButton("an offer", .idle, title: "Install", isEnabled: true),
        // A check may change the offer.
        BarButton("an offer while a check runs", .idle, isChecking: true, title: "Install", isEnabled: false),
        // In the same words as Open at login's note.
        BarButton("an offer in a fixture run", .idle, canInstall: false, title: "Install", isEnabled: false,
                  help: "Not available in fixture mode."),
        BarButton("downloading", .downloading(0.5), title: nil, isEnabled: false),
        BarButton("verifying", .verifying, title: nil, isEnabled: false),
        BarButton("ready", .ready, title: "Install and Relaunch", isEnabled: true,
                  help: "Replaces Join! with version 1.1.0 and opens it again."),
        // A check may find a newer release, which replaces the ready one.
        BarButton("ready while a check runs", .ready, isChecking: true, title: "Install and Relaunch", isEnabled: false,
                  help: "Replaces Join! with version 1.1.0 and opens it again."),
        BarButton("installing", .installing, title: nil, isEnabled: false),
        BarButton("failed", .failed(.checksum), title: "Download Page", isEnabled: true,
                  help: "The download doesn't match the release's checksum."),
        // Download Page only opens a page; the reason beats the fixture note.
        BarButton("failed in a fixture run while a check runs", .failed(.download), canInstall: false, isChecking: true,
                  title: "Download Page", isEnabled: true, help: "The download didn't finish."),
        BarButton("revealed, while a check runs", .revealed(URL(fileURLWithPath: "/tmp/Join.app")), isChecking: true,
                  title: "Show in Finder", isEnabled: true),
    ])
    func barButton(_ button: BarButton) {
        #expect(UpdateCopy.barButtonTitle(install: button.install) == button.title)
        #expect(UpdateCopy.barButtonEnabled(install: button.install, canInstall: button.canInstall, isChecking: button.isChecking) == button.isEnabled)
        #expect(UpdateCopy.barButtonHelp(version: Self.newer, install: button.install, canInstall: button.canInstall) == button.help)
    }
}
