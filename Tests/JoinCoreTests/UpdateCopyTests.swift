import Foundation
import Testing
@testable import JoinCore

struct UpdateCopyTests {
    private let current = AppVersion(major: 1, minor: 0, patch: 0)
    private let newer = AppVersion(major: 1, minor: 1, patch: 0)
    private let checked = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private var update: AvailableUpdate {
        AvailableUpdate(
            version: newer,
            pageURL: URL(string: "https://github.com/Poliuk/join/releases/tag/v1.1.0")!,
            downloadURL: URL(string: "https://github.com/Poliuk/join/releases/download/v1.1.0/Join.zip")!,
            sha256: nil,
            size: 2_486_395
        )
    }

    private var available: UpdateStatus { .available(update) }
    private var unsupported: UpdateStatus { .unsupported(AppVersion(major: 1, minor: 2, patch: 0), minimumSystem: "15.0") }

    @Test func settingsTitles() {
        #expect(UpdateCopy.sectionTitle == "Updates")
        #expect(UpdateCopy.automaticChecksTitle == "Check for updates automatically")
        #expect(UpdateCopy.checkNowTitle == "Check Now")
        #expect(UpdateCopy.installTitle == "Install")
        #expect(UpdateCopy.installAndRelaunchTitle == "Install and Relaunch")
    }

    @Test func installFixtureNoteMatchesOpenAtLogins() {
        #expect(UpdateCopy.installFixtureNote == "Not available in fixture mode.")
        #expect(UpdateCopy.installFixtureNote == SettingsOptions.openAtLoginFixtureNote)
    }

    @Test func statusLineAfterChecks() {
        func line(_ status: UpdateStatus, after seconds: TimeInterval) -> String {
            UpdateCopy.statusLine(current: current, status: status, offered: nil, lastCheck: checked, now: checked.addingTimeInterval(seconds))
        }
        #expect(line(.upToDate, after: 10) == "Join! 1.0.0 · Checked just now")
        #expect(line(.upToDate, after: 60) == "Join! 1.0.0 · Checked 1 minute ago")
        #expect(line(.upToDate, after: 5 * 60) == "Join! 1.0.0 · Checked 5 minutes ago")
        #expect(line(.upToDate, after: 3600) == "Join! 1.0.0 · Checked 1 hour ago")
        #expect(line(.upToDate, after: 3 * 3600 + 59 * 60) == "Join! 1.0.0 · Checked 3 hours ago")
        #expect(line(.upToDate, after: 24 * 3600) == "Join! 1.0.0 · Checked 1 day ago")
        #expect(line(.upToDate, after: 50 * 3600) == "Join! 1.0.0 · Checked 2 days ago")
        #expect(line(.upToDate, after: -3600) == "Join! 1.0.0 · Checked just now", "the clock moved back")
        #expect(line(.unknown, after: 5 * 60) == "Join! 1.0.0 · Checked 5 minutes ago", "a check stored by an earlier run")
    }

    @Test func statusLineWhileCheckingFailedNeverCheckedAvailableAndUnsupported() {
        func line(_ status: UpdateStatus, lastCheck: Date? = nil) -> String {
            UpdateCopy.statusLine(current: current, status: status, offered: nil, lastCheck: lastCheck, now: checked)
        }
        #expect(line(.checking) == "Join! 1.0.0 · Checking…")
        #expect(line(.checking, lastCheck: checked) == "Join! 1.0.0 · Checking…")
        #expect(line(.failed) == "Join! 1.0.0 · Couldn't check for updates")
        #expect(line(.failed, lastCheck: checked) == "Join! 1.0.0 · Couldn't check for updates")
        #expect(line(.unknown) == "Join! 1.0.0")
        #expect(line(.upToDate) == "Join! 1.0.0")
        #expect(line(available) == "Join! 1.1.0 is available")
        #expect(line(available, lastCheck: checked) == "Join! 1.1.0 is available")
        #expect(line(unsupported) == "Join! 1.2.0 needs macOS 15.0 or later")
        #expect(line(unsupported, lastCheck: checked) == "Join! 1.2.0 needs macOS 15.0 or later")
    }

    @Test func statusLineNamesTheOfferWhateverTheStatus() {
        func line(_ status: UpdateStatus, lastCheck: Date? = nil) -> String {
            UpdateCopy.statusLine(current: current, status: status, offered: update, lastCheck: lastCheck, now: checked)
        }
        #expect(line(.checking) == "Join! 1.1.0 is available", "a recheck under way")
        #expect(line(.failed) == "Join! 1.1.0 is available", "a recheck that failed")
        #expect(line(.unknown) == "Join! 1.1.0 is available", "remembered from an earlier run")
        #expect(line(.upToDate, lastCheck: checked) == "Join! 1.1.0 is available", "an older check")
        #expect(line(available) == "Join! 1.1.0 is available")
        let later = AvailableUpdate(
            version: AppVersion(major: 1, minor: 2, patch: 0),
            pageURL: URL(string: "https://github.com/Poliuk/join/releases/tag/v1.2.0")!,
            downloadURL: URL(string: "https://github.com/Poliuk/join/releases/download/v1.2.0/Join.zip")!,
            sha256: nil,
            size: 2_500_000
        )
        #expect(line(.available(later)) == "Join! 1.1.0 is available", "the offer, which Install installs, wins")
    }

    @Test func statusLineWithoutAReadableVersion() {
        #expect(UpdateCopy.statusLine(current: nil, status: .unknown, offered: nil, lastCheck: nil, now: checked) == "Join!")
        #expect(UpdateCopy.statusLine(current: nil, status: .failed, offered: nil, lastCheck: nil, now: checked) == "Join! · Couldn't check for updates")
    }

    @Test func unsupportedMessage() {
        #expect(
            UpdateCopy.unsupported(AppVersion(major: 1, minor: 2, patch: 0), minimumSystem: "15.0")
                == "Join! 1.2.0 needs macOS 15.0 or later"
        )
        #expect(UpdateCopy.unsupported(AppVersion(major: 2, minor: 0, patch: 0), minimumSystem: "26") == "Join! 2.0.0 needs macOS 26 or later")
    }

    @Test func failureReasons() {
        let reasons: [(UpdateFailure, String)] = [
            (.download, "The download didn't finish."),
            (.tooLarge, "The download is larger than 100 MB."),
            (.checksum, "The download doesn't match the release's checksum."),
            (.unzip, "The download couldn't be unzipped."),
            (.notJoin, "The downloaded app doesn't match the release."),
            (.wrongArchitecture, "This version doesn't run on this Mac's processor."),
            (.unsupportedSystem("15.0"), "This version needs macOS 15.0 or later."),
            (.unsupportedSystem("26"), "This version needs macOS 26 or later."),
            (.signature, "The downloaded app's code signature isn't valid."),
            (.save, "The new copy couldn't be saved."),
            (.relaunch, "Join! couldn't reopen itself. Quit it and open it again to finish."),
        ]
        for (failure, reason) in reasons {
            #expect(UpdateCopy.failureReason(failure) == reason, "\(failure)")
        }
    }

    @Test func checkedLabel() {
        #expect(UpdateCopy.checkedLabel(lastChecked: checked, now: checked) == "Checked just now")
        #expect(UpdateCopy.checkedLabel(lastChecked: checked, now: checked.addingTimeInterval(14 * 60 + 30)) == "Checked 14 minutes ago")
    }

    @Test func barMessages() {
        func message(_ install: UpdateInstallState) -> String {
            UpdateCopy.barMessage(version: newer, install: install)
        }
        #expect(UpdateCopy.available(newer) == "Join! 1.1.0 is available")
        #expect(message(.idle) == "Join! 1.1.0 is available")
        #expect(message(.downloading(0.45)) == "Downloading Join! 1.1.0… 45%")
        #expect(message(.downloading(0)) == "Downloading Join! 1.1.0… 0%")
        #expect(message(.downloading(1)) == "Downloading Join! 1.1.0… 100%")
        #expect(message(.downloading(0.294)) == "Downloading Join! 1.1.0… 29%")
        #expect(message(.downloading(1.5)) == "Downloading Join! 1.1.0… 100%")
        #expect(message(.downloading(nil)) == "Downloading Join! 1.1.0…")
        #expect(message(.downloading(.nan)) == "Downloading Join! 1.1.0…")
        #expect(message(.verifying) == "Verifying Join! 1.1.0…")
        #expect(UpdateCopy.ready(newer) == "Install 1.1.0")
        #expect(message(.ready) == "Install 1.1.0")
        #expect(message(.installing) == "Installing Join! 1.1.0…")
        #expect(message(.failed(.checksum)) == "Couldn't install Join! 1.1.0")
        #expect(message(.failed(.unsupportedSystem("15.0"))) == "Couldn't install Join! 1.1.0")
        #expect(
            message(.revealed(URL(fileURLWithPath: "/Users/me/Downloads/Join 1.1.0/Join.app")))
                == "Quit Join!, then move Join! 1.1.0 to Applications"
        )
    }

    @Test func barButtons() {
        #expect(UpdateCopy.barButtonTitle(install: .idle) == "Install")
        #expect(UpdateCopy.barButtonTitle(install: .downloading(0.5)) == nil)
        #expect(UpdateCopy.barButtonTitle(install: .downloading(nil)) == nil)
        #expect(UpdateCopy.barButtonTitle(install: .verifying) == nil)
        #expect(UpdateCopy.barButtonTitle(install: .ready) == "Install and Relaunch")
        #expect(UpdateCopy.barButtonTitle(install: .installing) == nil)
        #expect(UpdateCopy.barButtonTitle(install: .failed(.download)) == "Download Page")
        #expect(UpdateCopy.barButtonTitle(install: .revealed(URL(fileURLWithPath: "/tmp/Join.app"))) == "Show in Finder")
    }

    @Test func barButtonEnabled() {
        func enabled(_ install: UpdateInstallState, canInstall: Bool = true, isChecking: Bool = false) -> Bool {
            UpdateCopy.barButtonEnabled(install: install, canInstall: canInstall, isChecking: isChecking)
        }
        #expect(enabled(.idle))
        #expect(!enabled(.idle, isChecking: true), "Install waits for a check, which may change the offer")
        #expect(!enabled(.idle, canInstall: false), "a fixture run that can't install")
        #expect(enabled(.ready))
        #expect(!enabled(.ready, isChecking: true), "a check may find a newer release, which replaces the ready one")
        #expect(!enabled(.downloading(0.5)))
        #expect(!enabled(.verifying))
        #expect(!enabled(.installing))
        #expect(enabled(.failed(.download)))
        #expect(enabled(.failed(.download), canInstall: false, isChecking: true), "Download Page only opens a page")
        #expect(enabled(.revealed(URL(fileURLWithPath: "/tmp/Join.app")), isChecking: true))
    }

    @Test func barButtonHelp() {
        func help(_ install: UpdateInstallState, canInstall: Bool = true) -> String? {
            UpdateCopy.barButtonHelp(version: newer, install: install, canInstall: canInstall)
        }
        #expect(help(.idle) == nil)
        #expect(help(.idle, canInstall: false) == "Not available in fixture mode.")
        #expect(help(.ready) == "Replaces Join! with version 1.1.0 and opens it again.")
        #expect(UpdateCopy.installAndRelaunchHelp(newer) == "Replaces Join! with version 1.1.0 and opens it again.")
        #expect(help(.failed(.checksum)) == "The download doesn't match the release's checksum.")
        #expect(help(.failed(.relaunch)) == "Join! couldn't reopen itself. Quit it and open it again to finish.")
        #expect(help(.downloading(nil)) == nil)
        #expect(help(.verifying) == nil)
        #expect(help(.installing) == nil)
        #expect(help(.revealed(URL(fileURLWithPath: "/tmp/Join.app"))) == nil)
    }
}
