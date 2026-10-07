import Foundation

/// The words for checking and installing updates, in Settings › General › Updates and on the menu bar
/// panel's update bar.
public enum UpdateCopy {
    // MARK: Settings

    public static let sectionTitle = "Updates"
    public static let automaticChecksTitle = "Check for updates automatically"
    public static let checkNowTitle = "Check Now"
    public static let installTitle = "Install"
    /// Under Install in a fixture run (unless JOIN_FIXTURE_UPDATE=live), in the same words as Open at login's note.
    public static let installFixtureNote = "Not available in fixture mode."

    /// The line beside Check Now: "Join! 1.0.0 · Checked 5 minutes ago", "Join! 1.0.0 · Checking…",
    /// "Join! 1.0.0 · Couldn't check for updates", "Join! 1.0.0" before the first check,
    /// "Join! 1.1.0 is available", or "Join! 1.2.0 needs macOS 15.0 or later". While an update is
    /// `offered`, the line names it whatever the status, so Install never sits beside a line without a
    /// version. `current` is nil in a build without a readable version.
    public static func statusLine(
        current: AppVersion?,
        status: UpdateStatus,
        offered: AvailableUpdate?,
        lastCheck: Date?,
        now: Date
    ) -> String {
        if let offered { return available(offered.version) }
        let name = current.map { "Join! \($0)" } ?? "Join!"
        switch status {
        case .available(let update):
            return available(update.version)
        case .unsupported(let version, let minimumSystem):
            return unsupported(version, minimumSystem: minimumSystem)
        case .checking:
            return name + " · Checking…"
        case .failed:
            return name + " · Couldn't check for updates"
        case .unknown, .upToDate:
            guard let lastCheck else { return name }
            return name + " · " + checkedLabel(lastChecked: lastCheck, now: now)
        }
    }

    /// "Checked just now", "Checked 5 minutes ago", …, counted as `SettingsOptions.updatedLabel` counts.
    public static func checkedLabel(lastChecked: Date, now: Date) -> String {
        "Checked " + SettingsOptions.relativeTime(since: lastChecked, now: now)
    }

    /// "Join! 1.1.0 is available".
    public static func available(_ version: AppVersion) -> String {
        "Join! \(version) is available"
    }

    /// "Join! 1.2.0 needs macOS 15.0 or later".
    public static func unsupported(_ version: AppVersion, minimumSystem: String) -> String {
        "Join! \(version) needs macOS \(minimumSystem) or later"
    }

    /// Why an install stopped, under the status line and as the bar's tooltip: "The download didn't
    /// finish.", "This version needs macOS 15.0 or later.", …
    public static func failureReason(_ failure: UpdateFailure) -> String {
        switch failure {
        case .download: return "The download didn't finish."
        case .tooLarge: return "The download is larger than \(UpdateCheck.maximumDownloadSize / 1024 / 1024) MB."
        case .checksum: return "The download doesn't match the release's checksum."
        case .unzip: return "The download couldn't be unzipped."
        case .notJoin: return "The downloaded app doesn't match the release."
        case .wrongArchitecture: return "This version doesn't run on this Mac's processor."
        case .unsupportedSystem(let minimum): return "This version needs macOS \(minimum) or later."
        case .signature: return "The downloaded app's code signature isn't valid."
        case .save: return "The new copy couldn't be saved."
        case .relaunch: return "Join! couldn't reopen itself. Quit it and open it again to finish."
        }
    }

    // MARK: Panel bar

    public static let downloadPageTitle = "Download Page"
    public static let showInFinderTitle = "Show in Finder"

    /// "Join! 1.1.0 is available", "Downloading Join! 1.1.0… 45%" (no percent while the size is unknown),
    /// "Installing Join! 1.1.0…", "Couldn't install Join! 1.1.0", or, once revealed,
    /// "Quit Join!, then move Join! 1.1.0 to Applications".
    public static func barMessage(version: AppVersion, install: UpdateInstallState) -> String {
        switch install {
        case .idle:
            return available(version)
        case .downloading(let fraction):
            guard let percent = fraction.flatMap(wholePercent) else { return "Downloading Join! \(version)…" }
            return "Downloading Join! \(version)… \(percent)%"
        case .installing:
            return "Installing Join! \(version)…"
        case .failed:
            return "Couldn't install Join! \(version)"
        case .revealed:
            return "Quit Join!, then move Join! \(version) to Applications"
        }
    }

    /// Install, then Download Page after a failure or Show in Finder once revealed; none while downloading
    /// or installing.
    public static func barButtonTitle(install: UpdateInstallState) -> String? {
        switch install {
        case .idle: return installTitle
        case .downloading, .installing: return nil
        case .failed: return downloadPageTitle
        case .revealed: return showInFinderTitle
        }
    }

    /// 0 to 100, to the nearest whole percent; nil for a fraction that isn't a number.
    private static func wholePercent(_ fraction: Double) -> Int? {
        guard fraction.isFinite else { return nil }
        return Int((min(max(fraction, 0), 1) * 100).rounded())
    }
}
