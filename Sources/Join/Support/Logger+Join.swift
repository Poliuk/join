import OSLog

/// The app's log categories, each declared once, under one subsystem. Nonisolated: a `Logger` is `Sendable`,
/// and the update download and install log off the main actor.
nonisolated extension Logger {
    private static let subsystem = "com.poliuk.join"

    /// Saving and reading the alerts' snoozes, dismissals and pause.
    static let alerts = Logger(subsystem: subsystem, category: "alerts")
    /// Calendar access and reads.
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    /// Fixture runs: the JOIN_FIXTURE scenario and the script hooks' snapshots.
    static let fixture = Logger(subsystem: subsystem, category: "fixture")
    /// The notification cards: saving and reading their states.
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    /// Settings that reach the system: Open at login, System Settings' panes.
    static let settings = Logger(subsystem: subsystem, category: "settings")
    /// The update check, the download and the install.
    static let updates = Logger(subsystem: subsystem, category: "updates")
}
