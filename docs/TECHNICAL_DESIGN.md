# Technical Design — Join!

*Status: approved 2026-10-05, updated to match the implementation · Companion to PRODUCT_BRIEF.md*

## 1. Platform and stack

**Decision: native macOS app in Swift, SwiftUI for views, AppKit where SwiftUI falls short (the alert windows). No third-party runtime dependencies.**

| Requirement | Why native wins |
|---|---|
| Read calendars | EventKit is an Apple framework; only reachable from native code. |
| Full-screen overlay above everything, on every display, over other apps' full-screen Spaces | Needs `NSWindow` level and collection-behavior control. Electron exposes some of this but not reliably across Spaces. |
| Menu bar app with no Dock icon | `LSUIElement` + `MenuBarExtra` / `NSStatusItem`; first-class in AppKit. |
| Tiny footprint, always running | A native agent app idles at ~20–30 MB. An Electron shell idles at 150 MB+ for a menu bar app. |

Considered and rejected:

- **Electron** (author's home turf via Studio): worst fit for a persistent menu bar utility; EventKit would need a native addon anyway.
- **Tauri**: lighter than Electron but the calendar and overlay pieces still end up as Swift plugins; you'd write the hard parts in Swift regardless.

Targets: **macOS 14+**, **Swift 5.10**, Swift Concurrency (`async/await`, `@MainActor`), `@Observable` for state. The project is a Swift Package, so the **Command Line Tools are enough to build**; Xcode is only needed to run the XCTest suite.

## 2. Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│  UI (SwiftUI)                                                     │
│  MenuBarPanelView   AlertView   SettingsView (General/Calendars/  │
│                                              Appearance)          │
└──────────┬──────────────┬────────────────────────┬────────────────┘
           │              │                        │
┌──────────▼──────────────▼────────────────────────▼────────────────┐
│  App state (@Observable, @MainActor)                              │
│  MeetingStore      AlertCoordinator      Preferences              │
│  (meetings, sync)  (schedule/present/    (UserDefaults-backed)    │
│                     snooze/dismiss)                               │
└──────────┬──────────────┬────────────────────────────────────────┘
           │              │
┌──────────▼───────┐ ┌────▼─────────────────┐ ┌──────────────────────┐
│ CalendarService  │ │ AlertScheduler       │ │ AlertWindowController│
│ (protocol)       │ │ (pure logic, tested) │ │ (AppKit, one NSWindow│
│ └ EventKitCal…   │ │                      │ │  per NSScreen)       │
│ └ (later) Google │ └──────────────────────┘ └──────────────────────┘
└──────────────────┘
        │
   EventKit (EKEventStore)  ← Google account via System Settings › Internet Accounts
```

Principles:

- **One source of truth for meetings.** `MeetingStore` owns `[Meeting]`; everything else reads from it.
- **Scheduling is pure.** `AlertScheduler` takes `(meetings, preferences, alertStates, now)` and returns the next thing to do. No timers, no windows. Fully unit-testable.
- **Side effects live at the edges.** `AlertCoordinator` owns the timer and calls the scheduler; `AlertWindowController` owns windows.
- **Calendar backend is swappable.** `CalendarService` is a protocol so a direct Google API implementation can be dropped in later.

## 3. Data model

```swift
struct Meeting: Identifiable, Hashable, Sendable {
    /// eventIdentifier + start timestamp — recurring events share an
    /// eventIdentifier, so the occurrence start is part of the id.
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let calendarColor: CGColor
    let location: String?
    let notes: String?
    let url: URL?
    let myStatus: ParticipationStatus   // accepted, tentative, declined, unknown
    var joinURL: URL?                    // filled by MeetingLinkDetector
}

enum AlertState: Equatable {
    case pending                 // will fire at start - leadTime
    case snoozed(until: Date)
    case showing
    case dismissed               // no more alerts for this occurrence
}

struct Preferences {                       // persisted in UserDefaults
    var leadTime: TimeInterval = 180
    var snoozeDurations: [TimeInterval] = [60, 300]
    var showOnAllScreens = true
    var autoCloseAfter: TimeInterval? = 15 * 60
    var launchAtLogin = false
    var soundName: String? = nil
    var soundRepeats = false
    var enabledCalendarIDs: Set<String>    // empty = "not yet chosen" → all
    var menuBarShowsNextEvent = true
    var appearance: AlertAppearance
}

struct AlertAppearance: Codable {
    var textColor: RGBA
    var blurMode: BlurMode            // .dark, .light, .none
    var backgroundTint: RGBA?         // nil = off
    var backgroundOpacity: Double
    var buttonForeground: RGBA
    var buttonBackground: RGBA?
    var buttonOpacity: Double
    var primaryForeground: RGBA
    var primaryBackground: RGBA?
    var primaryOpacity: Double
    static let `default`: AlertAppearance
}
```

`RGBA` is a small Codable struct so the theme round-trips to JSON (import/export later is then free).

## 4. Calendar integration (EventKit)

**Permission.** `EKEventStore.requestFullAccessToEvents()` (macOS 14 API). `Info.plist` needs `NSCalendarsFullAccessUsageDescription`. Entitlement `com.apple.security.personal-information.calendars` if sandboxed (recommended; nothing here needs to escape the sandbox).

**Calendars.** `store.calendars(for: .event)` grouped by `calendar.source.title` (e.g. a work account and a personal account appear as separate groups). Calendar colors are converted to a Codable `RGBA` so `Meeting` stays free of AppKit types. The Calendars tab toggles `calendarIdentifier`s into `Preferences.enabledCalendarIDs`.

**Fetching.** Window is `now − 1 h … now + 7 days`:

```swift
let predicate = store.predicateForEvents(withStart: from, end: to, calendars: enabled)
let events = store.events(matching: predicate)   // recurrences already expanded
```

Mapping rules:

- Skip `isAllDay`.
- Skip when the current user's `participantStatus == .declined` (find the `EKParticipant` with `isCurrentUser`).
- Skip `status == .canceled`.
- Tentative and unknown are included: you can't know whether the user will attend, so alerting is the safe default.

**Staying fresh.** Refetch on:

- `NSNotification.Name.EKEventStoreChanged` (fires when the system calendar database changes, including after a Google sync),
- `NSWorkspace.didWakeNotification`,
- a change to `enabledCalendarIDs`,
- a 15-minute safety-net timer.

Each refetch replaces `MeetingStore.meetings` and asks `AlertCoordinator` to re-plan. Google sync latency itself is governed by Calendar.app › Settings › Accounts › Refresh Calendars; the README will tell users to set it to "Every minute" or "Every 5 minutes".

**Alternative backend (P2, not built now).** `GoogleCalendarService: CalendarService` would use OAuth 2.0 with PKCE via `ASWebAuthenticationSession` and a loopback redirect, `calendar.readonly` scope, tokens in Keychain, `events.list` with `syncToken` every 60 s, and `conferenceData.entryPoints` for join links. Blocked on creating a Google Cloud project and going through OAuth verification.

## 5. Alert scheduling

The heart of the app. Kept pure so it can be tested exhaustively.

```swift
struct AlertPlan: Equatable {
    var fireAt: Date
    var meetings: [Meeting]      // ≥1; several meetings may share a fire time
}

enum AlertScheduler {
    /// Returns the next alert to fire, or nil.
    static func nextPlan(meetings: [Meeting],
                         states: [Meeting.ID: AlertState],
                         prefs: Preferences,
                         now: Date) -> AlertPlan?
}
```

Rules:

1. For each meeting with state `.pending`: `fireAt = start − leadTime`. If `fireAt < now` but `end > now` (we missed it: app launched late, Mac was asleep) → fire **now**, unless the meeting already started more than 5 minutes ago (`lateAlertGrace`), in which case it is skipped: alerting for a meeting you are presumably already in is noise.
2. `.snoozed(until)` → `fireAt = until`, again clamped to `now` if in the past, and dropped once `end < now`.
3. `.showing` and `.dismissed` produce nothing.
4. Meetings whose `fireAt` fall within 1 second of the earliest one are grouped into a single `AlertPlan`, so two back-to-back meetings produce one alert listing both instead of two stacked windows.
5. If alerts are **paused** (menu bar toggle), return nil.

`AlertCoordinator` (side effects):

- Holds one `DispatchSourceTimer`. On every re-plan it cancels and re-arms the timer for `plan.fireAt`, with 0.5 s leeway.
- Also runs a 30-second **heartbeat** that calls `nextPlan` and fires anything overdue. This catches the cases where a one-shot timer silently fails: system sleep, clock/timezone change, the process being suspended by App Nap (which we also disable via `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` while an alert is pending within 5 minutes).
- On fire: mark meetings `.showing`, ask `AlertWindowController` to present, start the auto-close timer if configured.
- User actions from the alert: Dismiss → `.dismissed`; Snooze(d) → `.snoozed(until: now + d)`; Snooze until event → `.snoozed(until: start)`; Join → open URL then `.dismissed`.
- `AlertState`s are persisted (`UserDefaults`, each with the meeting's end as expiry, pruned when expired) so a relaunch during a snooze doesn't re-alert or lose the snooze.
- One alert at a time: while an alert is on screen, nothing else fires; the next plan is computed when it closes.
- If a meeting is edited (start moves) its `id` changes → new occurrence, state resets to `.pending`. Cancelled meetings disappear from the store; if their alert is showing, the window closes.

## 6. Alert window (AppKit)

One `NSWindow` per `NSScreen` when `showOnAllScreens`, otherwise `NSScreen.main`. Recreated on `NSApplication.didChangeScreenParametersNotification` (display hot-plug while showing).

```swift
let window = NSWindow(contentRect: screen.frame,
                      styleMask: [.borderless],
                      backing: .buffered, defer: false)
window.level = .screenSaver                       // above menu bar and full-screen apps
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false
window.contentView = NSHostingView(rootView: AlertView(...))
window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
```

Background: an `NSVisualEffectView` (`material: .fullScreenUI`, `blendingMode: .behindWindow`) whose `appearance` is forced to `.darkAqua` / `.aqua` for the dark/light blur modes, or hidden for `.none`, plus a color layer for the tint at `backgroundOpacity`.

`AlertView` (SwiftUI): calendar-colored accent bar, title, time range, a `TimelineView(.periodic(from:by: 1))` countdown, optional location, buttons. The window becomes key so `Esc` (`.keyboardShortcut(.cancelAction)`) dismisses and `Return` triggers Join when present. Only the first window handles keys; the others mirror the content.

Multiple meetings in one plan render as a vertical stack with one button row.

## 7. Menu bar

`MenuBarExtra` with `.menuBarExtraStyle(.window)`:

- **Label:** SF Symbol `calendar` plus, when `menuBarShowsNextEvent` is on, a text label rendered from `MeetingStore.next` and refreshed every 30 s ("Board Meeting, in 12m" / "Board Meeting, now").
- **Panel:** `MenuBarPanelView`. Sections **Ongoing** and **Upcoming** with a Today / All segmented control; rows show color bar, title, time, location, a video-camera button when `joinURL != nil`. Footer: pause alerts toggle (`AlertCoordinator.isPaused`), Settings (`SettingsLink`), Quit.
- If calendar permission is missing, the panel shows an explanation and an "Open System Settings" button (`x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`).

If `MenuBarExtra` proves limiting (programmatic dismissal, sizing), fall back to `NSStatusItem` + `NSPopover` hosting the same SwiftUI view; the view doesn't change.

## 8. Settings window

SwiftUI `Settings` scene → `TabView` with three tabs. All controls bind to `Preferences`.

- **General:** lead time (min / sec steppers), two snooze durations (sliders 1–60 min), show alert on (all screens / main screen), auto-close toggle + minutes, alert sound picker (`/System/Library/Sounds` names, "none") + play repeatedly, launch at login (`SMAppService.mainApp.register()` / `.unregister()`).
- **Calendars:** `List` grouped by source with `Toggle`s. Unticking everything is allowed; the footer warns "No calendars selected, you won't get alerts."
- **Appearance:** form on the left (`ColorPicker`s, blur mode `Picker`, opacity `Slider`s), live `AlertView` preview on the right in a scaled-down frame with a fake meeting, **Show Demo Alert** (calls `AlertWindowController.present(demo:)`), **Reset to defaults**.

Persistence: `Preferences` is an `@Observable` class whose stored properties read/write `UserDefaults.standard` (theme encoded as JSON `Data`). No `@AppStorage` scattered across views; one owner.

## 9. Meeting link detection

```swift
enum MeetingLinkDetector {
    static func joinURL(in meeting: Meeting) -> URL?
}
```

Walks an ordered provider table; for each provider it checks `url`, `location`, then `notes`. A match from an earlier provider wins regardless of field:

| Provider | Pattern |
|---|---|
| Google Meet | `https://meet.google.com/[a-z]{3}-[a-z]{4}-[a-z]{3}` |
| Zoom | `https://[\w.-]*zoom\.us/(j|my|s)/[^\s>"]+` |
| Microsoft Teams | `https://teams\.microsoft\.com/l/meetup-join/[^\s>"]+` |
| Webex | `https://[\w.-]+\.webex\.com/[^\s>"]+` |
| Generic fallback | any `https://` URL in `location` only. The `url` field is excluded on purpose: calendar backends often put the event's own web page there, which would give every event a bogus Join button. |

Adding a provider is one table row plus a test case. Opening uses `NSWorkspace.shared.open(url)` (system default browser or handler).

## 10. Edge cases handled

| Case | Behaviour |
|---|---|
| Mac asleep through the fire time | On wake: refetch, `nextPlan` sees `fireAt < now < end` → fires immediately. |
| App launched 1 min before a meeting | Same path: fires on first plan. |
| Meeting created less than `leadTime` before start | `EKEventStoreChanged` → re-plan → fires now. |
| Meeting cancelled while alert showing | Store no longer contains it → coordinator closes the alert. |
| Meeting moved | New `id`, old state discarded, new occurrence scheduled. |
| Two meetings at the same time | One alert listing both. |
| Lead time changed in Settings | Re-plan; a meeting already `.dismissed` stays dismissed. |
| User in a full-screen app on another Space | `.canJoinAllSpaces` + `.fullScreenAuxiliary` + `.screenSaver` level shows over it. |
| Display plugged/unplugged during alert | Windows rebuilt from current `NSScreen.screens`. |
| Focus / Do Not Disturb on | Ignored by design; the whole point is to interrupt. Documented. |
| Calendar permission revoked at runtime | `EKEventStoreChanged` refetch returns nothing; menu bar panel shows the permission prompt. |
| Timezone change while running | Heartbeat re-plans with fresh `Date()`; events are stored as absolute instants. |

## 11. Repository layout

A Swift Package rather than an Xcode project, so contributors without Xcode can build it and the whole thing stays diff-friendly. Xcode opens `Package.swift` directly.

```
join/
├── Package.swift            JoinCore (library), Join (executable), JoinCoreTests
├── Sources/
│   ├── JoinCore/            Pure logic, Foundation + Observation only
│   │   Meeting, AlertState, AlertScheduler, MeetingLinkDetector,
│   │   MeetingTimeFormatter, Preferences, AlertAppearance, RGBA
│   └── Join/                The app
│       ├── App/             JoinApp (scenes), AppDelegate, AppModel (wiring)
│       ├── Calendar/        CalendarService (protocol), EventKitCalendarService, MeetingStore
│       ├── Alerts/          AlertCoordinator, AlertWindowController, AlertView
│       ├── MenuBar/         MenuBarLabel, MenuBarPanelView
│       ├── Settings/        SettingsView, GeneralTab, CalendarsTab, AppearanceTab
│       └── Support/         Observation helper, Color↔RGBA, SystemSounds, LaunchAtLogin
├── Tests/JoinCoreTests/     XCTest suites for everything in JoinCore
├── Resources/Info.plist     LSUIElement, usage description, bundle metadata
├── scripts/build-app.sh     Assembles build/Join.app and ad-hoc signs it
├── Makefile                 make app | run | test | clean
├── .github/workflows/ci.yml build + test + package on macos-14
└── docs/                    This document and the product brief
```

Bundle id `com.poliuk.join`, `LSUIElement = YES`.

## 12. Testing strategy

- **Unit tests (XCTest) on `JoinCore`:** `AlertScheduler` (every row of the edge-case table above with a fixed `now`), `MeetingLinkDetector` (one fixture per provider plus negatives), `MeetingTimeFormatter`, `MeetingFilter`, `Preferences` round-trip through an isolated `UserDefaults` suite, `AlertAppearance` JSON round-trip.
- `swift test` needs XCTest, which ships with Xcode, not with the Command Line Tools. CI runs the suite on every push; locally without Xcode the suite can't run.
- **Manual smoke checklist** for the UI: demo alert in light/dark, all screens vs main, snooze, full-screen app on another Space, sleep/wake with a meeting 2 minutes out.
- **No UI tests**; the AppKit window behaviour isn't meaningfully testable headless.

## 13. Build, CI, distribution

- **Build:** `make app` runs `scripts/build-app.sh`: `swift build -c release`, copies the binary and `Info.plist` into `build/Join.app`, and ad-hoc signs it (`codesign --sign -`). The ad-hoc signature is what lets TCC associate the calendar permission with the bundle. `make run` builds and opens it.
- **CI:** GitHub Actions on `macos-14`: `swift build`, `swift test`, `scripts/build-app.sh`, and the `.app` is uploaded as a workflow artifact.
- **Distribution:** unsigned/un-notarized by decision. Users build locally or download the CI artifact and right-click → Open once. Notarization (Developer ID + `notarytool`) can be added to `release.yml` later without touching the app.
- **Sandbox:** off. Sandboxing requires a real signing identity to be meaningful; nothing in the app needs it.
- **Auto-update:** not in v1. Sparkle 2 if wanted later.

## 14. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Google → macOS Calendar sync lag (up to the user's refresh interval) | A meeting created 10 min before start may not alert | Document the refresh-interval setting; safety-net refetch; direct Google API as P2 if it bites. |
| `MenuBarExtra(.window)` quirks (can't dismiss programmatically before opening a URL, fixed sizing) | Slightly clunky panel | Fallback to `NSStatusItem` + `NSPopover` is planned and cheap. |
| One-shot timers unreliable across sleep / App Nap | Missed alert | Heartbeat + overdue-fires-now rule + disabling App Nap near fire time. This is the most important correctness property; it gets the most tests. |
| No Apple Developer membership | Gatekeeper friction for users | Ship unsigned first; document right-click → Open; sign later. |
| EventKit doesn't expose structured conference data | Join link missed for exotic providers | Regex table + generic `https://` fallback from location; easy community contributions. |
| `.screenSaver` window level fights with macOS lock screen / actual screen saver | Alert hidden behind lock screen | Acceptable: if the screen is locked the user isn't there. The alert remains until dismissed. |

## 15. Delivery plan

| Milestone | Scope | Exit criterion |
|---|---|---|
| **M0 Scaffold** | Xcode project, `LSUIElement`, empty `MenuBarExtra`, CI green | App runs, icon in menu bar, `xcodebuild test` passes |
| **M1 Calendars** | EventKit permission, `EventKitCalendarService`, `MeetingStore`, Calendars tab, menu bar panel with Ongoing/Upcoming | Real meetings from Google show in the panel; toggling a calendar updates the list |
| **M2 Alerts** | `AlertScheduler` + tests, `AlertCoordinator`, `AlertWindowController`, `AlertView` with countdown/dismiss/snooze, persistence of alert states | Alert fires on time on all screens, snooze/dismiss work, survives sleep/wake and relaunch |
| **M3 Settings** | General tab, Appearance tab with live preview + demo alert, `Preferences` persistence | Every setting in the brief is changeable and takes effect without restart |
| **M4 Ship** | Link detection + Join, sound, launch at login, README, CI workflow | `make run` works on a clean Mac with only the Command Line Tools |

All five milestones were delivered in the initial implementation on 2026-10-05.
