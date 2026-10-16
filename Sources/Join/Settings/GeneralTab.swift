import AppKit
import OSLog
import SwiftUI
import JoinCore

/// The app and its menu bar item: Open at login, the Menu bar section with the starting-soon pill, which
/// events count, and updates. Both kinds of alert have their own pane, Alerts.
struct GeneralTab: View {
    @Environment(AppModel.self) private var model
    /// Read from the system on appear and whenever the app or the Settings window comes back, so
    /// approving Join! in System Settings clears the hint. Never read or written in a fixture run.
    @State private var loginItem: LoginItemStatus = .notRegistered
    /// Why the last click on Open at login didn't take; shown in place of the status's hint until the next read.
    @State private var loginItemFailure: String?

    /// Whether the menu bar item's contrast warning has been announced, or was already shown.
    @State private var announcedPillWarning = false

    var body: some View {
        @Bindable var preferences = model.preferences

        VStack(alignment: .leading, spacing: 22) {
            SettingsBox {
                SettingsSwitchRow(title: "Open at login", isOn: openAtLogin, separator: false, enabled: !model.isFixture)
                if let note = model.isFixture ? SettingsOptions.openAtLoginFixtureNote : loginItemFailure ?? SettingsOptions.openAtLoginHint(loginItem) {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(model.isFixture ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)
                }
            }

            // What the menu bar item shows, and how it looks once an event is starting soon. The preview
            // follows Shows, right above it.
            SettingsSection(title: SettingsOptions.menuBarSectionTitle) {
                SettingsRow(title: SettingsOptions.menuBarShowsTitle, separator: false) {
                    Picker(SettingsOptions.menuBarShowsTitle, selection: $preferences.menuBarDisplay) {
                        ForEach(MenuBarDisplay.allCases, id: \.self) { display in
                            Text(display.title).tag(display)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                startingSoonRows
            }

            EventsSection()

            SettingsSection(title: UpdateCopy.sectionTitle) {
                SettingsSwitchRow(title: UpdateCopy.automaticChecksTitle, isOn: $preferences.checksForUpdates, separator: false)
                SettingsSeparator()
                updateStatusRow
                updateNotes
            }
        }
        .padding(SettingsMetrics.panePadding)
        .onAppear {
            refreshLaunchAtLogin()
            announcedPillWarning = pill.contrastWarning(accent: accent) != nil
        }
        .task(id: pill) { await announcePillWarning() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if (notification.object as? NSWindow)?.identifier == .settingsWindow { refreshLaunchAtLogin() }
        }
    }

    // MARK: Open at login

    /// Only the user's clicks reach the login item; refreshing from the system just updates the switch.
    private var openAtLogin: Binding<Bool> {
        Binding(get: { SettingsOptions.opensAtLogin(loginItem) }, set: { setLaunchAtLogin($0) })
    }

    private func refreshLaunchAtLogin() {
        guard !model.isFixture else { return }
        loginItem = LaunchAtLogin.status
        loginItemFailure = nil
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard !model.isFixture else { return }
        do {
            if enabled != SettingsOptions.opensAtLogin(LaunchAtLogin.status) {
                try LaunchAtLogin.setEnabled(enabled)
            }
            refreshLaunchAtLogin()
        } catch {
            // The system's error and which way the switch went: nothing personal.
            Logger.settings.error("Open at login: \(enabled ? "register" : "unregister", privacy: .public) failed: \(String(describing: error), privacy: .public)")
            refreshLaunchAtLogin()
            loginItemFailure = error.localizedDescription
        }
    }

    // MARK: Menu bar

    private var pill: StartingSoonPill { model.preferences.startingSoonPill }

    /// The system accent as the pill draws it now.
    private var accent: RGBA { NSColor.controlAccentColor.rgba }

    private func updatePill(_ change: (inout StartingSoonPill) -> Void) {
        var updated = model.preferences.startingSoonPill
        change(&updated)
        model.preferences.startingSoonPill = updated
    }

    /// When the pill replaces the countdown, with the menu bar's preview beside it; its color, a sibling
    /// row since it doesn't depend on the time; and a Text row only while an earlier build's text color is
    /// stored. The contrast warning sits under them.
    @ViewBuilder
    private var startingSoonRows: some View {
        SettingsMinutesChoice(
            title: SettingsOptions.startingSoonRowTitle,
            presets: SettingsOptions.startingSoonMinutes,
            range: StartingSoonPill.minuteRange,
            presetTitle: SettingsOptions.startingSoonTitle(minutes:),
            unit: SettingsOptions.minutesBeforeUnit,
            fieldLabel: SettingsOptions.startingSoonFieldLabel,
            minutes: Binding(get: { pill.minutes }, set: { minutes in updatePill { $0.minutes = minutes } }),
            accessory: AnyView(MenuBarPillPreview(pill: pill, display: model.preferences.menuBarDisplay)),
            help: SettingsOptions.startingSoonHelp
        )

        SettingsRow(title: SettingsOptions.menuBarColorTitle) {
            SettingsColorChoice(
                title: SettingsOptions.menuBarColorAccessibilityTitle,
                wellLabel: SettingsOptions.menuBarColorWellLabel,
                choice: StartingSoonPill.colorChoice,
                automaticDot: .accent,
                stored: { model.preferences.startingSoonPill.fill },
                shown: { model.preferences.startingSoonPill.resolvedFill(accent: accent) },
                pick: { item in updatePill { $0.pickColor(item, accent: accent) } },
                setColor: { color in updatePill { $0.setFillColor(color) } }
            )
        }

        if pill.showsLegacyText, let text = pill.text {
            SettingsRow(title: LegacyTextRow.title) {
                SettingsLegacyTextChoice(
                    title: SettingsOptions.menuBarTextAccessibilityTitle,
                    wellLabel: SettingsOptions.menuBarTextWellLabel,
                    color: text,
                    clear: { updatePill { $0.clearLegacyText() } },
                    setColor: { color in updatePill { $0.text = color.withAlpha(1) } }
                )
            }
        }

        if let warning = pill.contrastWarning(accent: accent) {
            SettingsWarning(message: warning)
                .padding(.bottom, 10)
        }
    }

    /// Tells VoiceOver when the menu bar item's contrast warning appears. Debounced, so dragging in the
    /// color panel is read out once, with the ratio it settles on.
    private func announcePillWarning() async {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        let warning = pill.contrastWarning(accent: accent)
        defer { announcedPillWarning = warning != nil }
        guard let warning, !announcedPillWarning else { return }
        AccessibilityNotification.Announcement(warning).post()
    }

    // MARK: Updates

    /// "Join! 1.0.0 · Checked 5 minutes ago" or the update on offer, then how an install is going ("Install
    /// 1.1.0" once downloaded and verified), with Check Now and the update bar's button:
    /// Install, Install and Relaunch once ready, Download Page after a failed install, Show in Finder once
    /// revealed. Install and Install and Relaunch wait for a check under way, which may change the offer;
    /// Check Now works while an update is ready, and a newer release takes its place.
    private var updateStatusRow: some View {
        let checker = model.updateChecker
        let status = checker.status
        let offered = checker.offeredUpdate
        let lastCheck = checker.lastCheck
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(UpdateCopy.statusLine(
                        current: checker.currentVersion, status: status, offered: offered, lastCheck: lastCheck, now: context.date
                    ))
                }
                if let update = checker.offeredUpdate, checker.install != .idle {
                    Text(UpdateCopy.barMessage(version: update.version, install: checker.install))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(UpdateCopy.checkNowTitle) { checker.checkNow() }
                    .disabled(checker.currentVersion == nil || checker.isChecking || checker.isInstalling)
                if let update = checker.offeredUpdate {
                    let title = UpdateCopy.barButtonTitle(install: checker.install)
                    Button(title ?? UpdateCopy.installTitle) { model.performUpdateAction() }
                        .disabled(!UpdateCopy.barButtonEnabled(install: checker.install, canInstall: checker.canInstall, isChecking: checker.isChecking))
                        .help(UpdateCopy.barButtonHelp(version: update.version, install: checker.install, canInstall: checker.canInstall) ?? "")
                }
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 40)
    }

    /// Why the last install failed, or that a fixture run can't install.
    @ViewBuilder
    private var updateNotes: some View {
        let checker = model.updateChecker
        if case .failed(let failure) = checker.install {
            Text(UpdateCopy.failureReason(failure))
                .font(.subheadline)
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        } else if checker.offeredUpdate != nil, checker.install == .idle, !checker.canInstall {
            Text(UpdateCopy.installFixtureNote)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        }
    }
}

/// The menu bar item once an event is starting soon, as the menu bar draws it: the pill, with the text
/// that Shows asks for, composed as the menu bar composes it.
private struct MenuBarPillPreview: View {
    let pill: StartingSoonPill
    let display: MenuBarDisplay

    var body: some View {
        let text = MenuBarPresenter.startingSoonPreviewText(display: display, pill: pill)
        Image(nsImage: StatusItemImages.pill(text: text, style: pill))
            .accessibilityElement()
            .accessibilityLabel(SettingsOptions.menuBarPreviewLabel)
            .accessibilityValue(text ?? "")
            .accessibilityAddTraits(.isImage)
    }
}
