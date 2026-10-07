import XCTest
@testable import JoinCore

final class UpdateCopyTests: XCTestCase {
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

    func testSettingsTitles() {
        XCTAssertEqual(UpdateCopy.sectionTitle, "Updates")
        XCTAssertEqual(UpdateCopy.automaticChecksTitle, "Check for updates automatically")
        XCTAssertEqual(UpdateCopy.checkNowTitle, "Check Now")
        XCTAssertEqual(UpdateCopy.installTitle, "Install")
    }

    func testInstallFixtureNoteMatchesOpenAtLogins() {
        XCTAssertEqual(UpdateCopy.installFixtureNote, "Not available in fixture mode.")
        XCTAssertEqual(UpdateCopy.installFixtureNote, SettingsOptions.openAtLoginFixtureNote)
    }

    func testStatusLineAfterChecks() {
        func line(_ status: UpdateStatus, after seconds: TimeInterval) -> String {
            UpdateCopy.statusLine(current: current, status: status, offered: nil, lastCheck: checked, now: checked.addingTimeInterval(seconds))
        }
        XCTAssertEqual(line(.upToDate, after: 10), "Join! 1.0.0 · Checked just now")
        XCTAssertEqual(line(.upToDate, after: 60), "Join! 1.0.0 · Checked 1 minute ago")
        XCTAssertEqual(line(.upToDate, after: 5 * 60), "Join! 1.0.0 · Checked 5 minutes ago")
        XCTAssertEqual(line(.upToDate, after: 3600), "Join! 1.0.0 · Checked 1 hour ago")
        XCTAssertEqual(line(.upToDate, after: 3 * 3600 + 59 * 60), "Join! 1.0.0 · Checked 3 hours ago")
        XCTAssertEqual(line(.upToDate, after: 24 * 3600), "Join! 1.0.0 · Checked 1 day ago")
        XCTAssertEqual(line(.upToDate, after: 50 * 3600), "Join! 1.0.0 · Checked 2 days ago")
        XCTAssertEqual(line(.upToDate, after: -3600), "Join! 1.0.0 · Checked just now", "the clock moved back")
        XCTAssertEqual(line(.unknown, after: 5 * 60), "Join! 1.0.0 · Checked 5 minutes ago", "a check stored by an earlier run")
    }

    func testStatusLineWhileCheckingFailedNeverCheckedAvailableAndUnsupported() {
        func line(_ status: UpdateStatus, lastCheck: Date? = nil) -> String {
            UpdateCopy.statusLine(current: current, status: status, offered: nil, lastCheck: lastCheck, now: checked)
        }
        XCTAssertEqual(line(.checking), "Join! 1.0.0 · Checking…")
        XCTAssertEqual(line(.checking, lastCheck: checked), "Join! 1.0.0 · Checking…")
        XCTAssertEqual(line(.failed), "Join! 1.0.0 · Couldn't check for updates")
        XCTAssertEqual(line(.failed, lastCheck: checked), "Join! 1.0.0 · Couldn't check for updates")
        XCTAssertEqual(line(.unknown), "Join! 1.0.0")
        XCTAssertEqual(line(.upToDate), "Join! 1.0.0")
        XCTAssertEqual(line(available), "Join! 1.1.0 is available")
        XCTAssertEqual(line(available, lastCheck: checked), "Join! 1.1.0 is available")
        XCTAssertEqual(line(unsupported), "Join! 1.2.0 needs macOS 15.0 or later")
        XCTAssertEqual(line(unsupported, lastCheck: checked), "Join! 1.2.0 needs macOS 15.0 or later")
    }

    func testStatusLineNamesTheOfferWhateverTheStatus() {
        func line(_ status: UpdateStatus, lastCheck: Date? = nil) -> String {
            UpdateCopy.statusLine(current: current, status: status, offered: update, lastCheck: lastCheck, now: checked)
        }
        XCTAssertEqual(line(.checking), "Join! 1.1.0 is available", "a recheck under way")
        XCTAssertEqual(line(.failed), "Join! 1.1.0 is available", "a recheck that failed")
        XCTAssertEqual(line(.unknown), "Join! 1.1.0 is available", "remembered from an earlier run")
        XCTAssertEqual(line(.upToDate, lastCheck: checked), "Join! 1.1.0 is available", "an older check")
        XCTAssertEqual(line(available), "Join! 1.1.0 is available")
        let later = AvailableUpdate(
            version: AppVersion(major: 1, minor: 2, patch: 0),
            pageURL: URL(string: "https://github.com/Poliuk/join/releases/tag/v1.2.0")!,
            downloadURL: URL(string: "https://github.com/Poliuk/join/releases/download/v1.2.0/Join.zip")!,
            sha256: nil,
            size: 2_500_000
        )
        XCTAssertEqual(line(.available(later)), "Join! 1.1.0 is available", "the offer, which Install installs, wins")
    }

    func testStatusLineWithoutAReadableVersion() {
        XCTAssertEqual(UpdateCopy.statusLine(current: nil, status: .unknown, offered: nil, lastCheck: nil, now: checked), "Join!")
        XCTAssertEqual(UpdateCopy.statusLine(current: nil, status: .failed, offered: nil, lastCheck: nil, now: checked), "Join! · Couldn't check for updates")
    }

    func testUnsupported() {
        XCTAssertEqual(
            UpdateCopy.unsupported(AppVersion(major: 1, minor: 2, patch: 0), minimumSystem: "15.0"),
            "Join! 1.2.0 needs macOS 15.0 or later"
        )
        XCTAssertEqual(UpdateCopy.unsupported(AppVersion(major: 2, minor: 0, patch: 0), minimumSystem: "26"), "Join! 2.0.0 needs macOS 26 or later")
    }

    func testFailureReasons() {
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
            XCTAssertEqual(UpdateCopy.failureReason(failure), reason, "\(failure)")
        }
    }

    func testCheckedLabel() {
        XCTAssertEqual(UpdateCopy.checkedLabel(lastChecked: checked, now: checked), "Checked just now")
        XCTAssertEqual(UpdateCopy.checkedLabel(lastChecked: checked, now: checked.addingTimeInterval(14 * 60 + 30)), "Checked 14 minutes ago")
    }

    func testBarMessages() {
        func message(_ install: UpdateInstallState) -> String {
            UpdateCopy.barMessage(version: newer, install: install)
        }
        XCTAssertEqual(UpdateCopy.available(newer), "Join! 1.1.0 is available")
        XCTAssertEqual(message(.idle), "Join! 1.1.0 is available")
        XCTAssertEqual(message(.downloading(0.45)), "Downloading Join! 1.1.0… 45%")
        XCTAssertEqual(message(.downloading(0)), "Downloading Join! 1.1.0… 0%")
        XCTAssertEqual(message(.downloading(1)), "Downloading Join! 1.1.0… 100%")
        XCTAssertEqual(message(.downloading(0.294)), "Downloading Join! 1.1.0… 29%")
        XCTAssertEqual(message(.downloading(1.5)), "Downloading Join! 1.1.0… 100%")
        XCTAssertEqual(message(.downloading(nil)), "Downloading Join! 1.1.0…")
        XCTAssertEqual(message(.downloading(.nan)), "Downloading Join! 1.1.0…")
        XCTAssertEqual(message(.installing), "Installing Join! 1.1.0…")
        XCTAssertEqual(message(.failed(.checksum)), "Couldn't install Join! 1.1.0")
        XCTAssertEqual(message(.failed(.unsupportedSystem("15.0"))), "Couldn't install Join! 1.1.0")
        XCTAssertEqual(
            message(.revealed(URL(fileURLWithPath: "/Users/me/Downloads/Join 1.1.0/Join.app"))),
            "Quit Join!, then move Join! 1.1.0 to Applications"
        )
    }

    func testBarButtons() {
        XCTAssertEqual(UpdateCopy.barButtonTitle(install: .idle), "Install")
        XCTAssertNil(UpdateCopy.barButtonTitle(install: .downloading(0.5)))
        XCTAssertNil(UpdateCopy.barButtonTitle(install: .downloading(nil)))
        XCTAssertNil(UpdateCopy.barButtonTitle(install: .installing))
        XCTAssertEqual(UpdateCopy.barButtonTitle(install: .failed(.download)), "Download Page")
        XCTAssertEqual(UpdateCopy.barButtonTitle(install: .revealed(URL(fileURLWithPath: "/tmp/Join.app"))), "Show in Finder")
    }
}
