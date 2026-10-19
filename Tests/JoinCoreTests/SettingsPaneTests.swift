import Foundation
import Testing
@testable import JoinCore

struct SettingsPaneTests {
    /// The toolbar, in order: each pane's raw value (what the `openSettings` hook takes), its label, which is
    /// also the window's title, and its symbol. Alerts is second, as the user asked (2026-10-19); it was
    /// Full-Screen Alert until 1.3.0 and keeps the bell, the panel's Pause alerts symbol.
    @Test func theToolbar() {
        #expect(SettingsPane.allCases.map(\.rawValue) == ["general", "alerts", "calendars", "appearance"])
        #expect(SettingsPane.allCases.map(\.title) == ["General", "Alerts", "Calendars", "Appearance"])
        #expect(SettingsPane.allCases.map(\.symbolName) == ["gearshape", "bell", "calendar", "paintpalette"])
        #expect(SettingsPane.alerts.title == SettingsOptions.alertsPaneTitle)
    }

    /// The hook takes every raw value, and fullScreenAlert, the Alerts pane's raw value until 1.3.0, so scripts
    /// written for 1.2.x still open it.
    @Test(arguments: [
        ("general", SettingsPane.general),
        ("alerts", .alerts),
        ("fullScreenAlert", .alerts),
        ("calendars", .calendars),
        ("appearance", .appearance),
    ] as [(String, SettingsPane)])
    func theHookNamesAPane(_ argument: String, _ pane: SettingsPane) {
        #expect(SettingsPane(hookArgument: argument) == pane)
    }

    /// Anything else names no pane, so the hook opens Settings on whichever pane showed last. The old name is
    /// only an alias: it isn't a raw value, so nothing new is ever stored or reported under it.
    @Test(arguments: ["", "Alerts", "fullscreenalert", "full-screen-alert", "notifications"])
    func anythingElseNamesNoPane(_ argument: String) {
        #expect(SettingsPane(hookArgument: argument) == nil)
    }

    @Test func theOldNameIsNotARawValue() {
        #expect(SettingsPane(rawValue: "fullScreenAlert") == nil)
    }
}
