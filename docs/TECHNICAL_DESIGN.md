# Technical Design — Join!

*Status: approved 2026-10-05, updated to match the implementation after the redesign, for in-app updates and for 1.2.0 (2026-10-07, Settings regroup 2026-10-08) · Companion to PRODUCT_BRIEF.md*

## 1. Platform and stack

**Decision: native macOS app in Swift, SwiftUI for views, AppKit where SwiftUI falls short (the status item, the menu bar panel window, the alert windows and the Settings window). No third-party runtime dependencies.**

| Requirement | Why native wins |
|---|---|
| Read calendars | EventKit is an Apple framework; only reachable from native code. |
| Full-screen overlay above everything, on every display, over other apps' full-screen Spaces | Needs `NSWindow` level and collection-behavior control. Electron exposes some of this but not reliably across Spaces. |
| Menu bar app with no Dock icon | `LSUIElement` + `NSStatusItem`; first-class in AppKit. |
| Tiny footprint, always running | A native agent app idles at ~20–30 MB. An Electron shell idles at 150 MB+ for a menu bar app. |

Considered and rejected:

- **Electron** (author's home turf via Studio): worst fit for a persistent menu bar utility; EventKit would need a native addon anyway.
- **Tauri**: lighter than Electron but the calendar and overlay pieces still end up as Swift plugins; you'd write the hard parts in Swift regardless.

Targets: **macOS 14+**, **Swift 5.10**, Swift Concurrency (`async/await`, `@MainActor`), `@Observable` for state. The project is a Swift Package, so the **Command Line Tools are enough to build**; Xcode is only needed to run the XCTest suite.

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  UI (SwiftUI views in AppKit windows)                               │
│  MenuBarPanelView         AlertView             General, Calendars, │
│  in MenuBarPanelWindow    in one AlertWindow    Full-Screen Alert,  │
│  (StatusItemController)   per target screen     Appearance panes in │
│                                                 SettingsWindow…     │
└──────────┬────────────────────────┬──────────────────────┬──────────┘
           │                        │                      │
┌──────────▼────────────────────────▼──────────────────────▼──────────┐
│  App state (@Observable, @MainActor)                                │
│  AppModel: wiring, and a clock that ticks on :00 and :30            │
│  MeetingStore       AlertCoordinator             Preferences        │
│  (meetings, sync)   (schedule/present/snooze/    (UserDefaults-     │
│                      dismiss, PauseState)         backed)           │
│  UpdateChecker (daily check, Install)                               │
└──────────┬────────────────────────┬─────────────────────────────────┘
           │                        │
┌──────────▼──────────┐ ┌───────────▼───────────────┐ ┌───────────────────────┐
│ CalendarService     │ │ JoinCore (pure, tested)   │ │ AlertWindowController │
│ (protocol)          │ │ AlertScheduler            │ │ (AppKit, one NSPanel  │
│ └ EventKitCal…      │ │ MenuBarPresenter          │ │  per target screen)   │
│ └ FixtureCal… (dev) │ │ PanelPresenter            │ └───────────────────────┘
│ └ (later) Google    │ │ AlertCountdown, palette   │ ┌───────────────────────┐
└─────────────────────┘ │ UpdateCheck, AppVersion   │ │ ReleaseFeed           │
        │               └───────────────────────────┘ │ (protocol)            │
        │                                             │ └ GitHubReleaseFeed   │
        │                                             │ └ FixtureRel… (dev)   │
        │                                             │ UpdateInstaller       │
        │                                             └───────────┬───────────┘
        │                                                         │
        │                                                  GitHub Releases
   EventKit (EKEventStore)  ← Google account via System Settings › Internet Accounts
```

Principles:

- **One source of truth for meetings.** `MeetingStore` owns `[Meeting]`; everything else reads from it.
- **Scheduling is pure.** `AlertScheduler` takes `(meetings, alertStates, leadTime, isPaused, now)` and returns the next thing to do. No timers, no windows. Fully unit-testable.
- **Presentation is pure too.** What the menu bar item says, what the panel lists, the alert's countdown wording, resolved colors and screens, and what the Settings pop-ups show are computed in `JoinCore` (`MenuBarPresenter`, `PanelPresenter`, `LocationFormatter`, `AlertCountdown`, `AlertAppearance.palette`, `AlertScreens`, `SettingsOptions`, `MinutesChoice`, `ColorChoice`, `AlertColorRow`, `UpdateCopy`) from plain values and a `now`. The SwiftUI views only lay the results out. Whether a release is an update, and when to check for one, is decided there too (`UpdateCheck`).
- **Side effects live at the edges.** `AlertCoordinator` owns the timer and calls the scheduler; `AlertWindowController` and `StatusItemController` own windows; `ReleaseFeed` and `UpdateInstaller` do the update's networking and file work (§14).
- **Calendar backend is swappable.** `CalendarService` is a protocol. Besides EventKit there is a fixture implementation for checking the UI (§12), and a direct Google API implementation can be dropped in later. `ReleaseFeed` works the same way for updates: GitHub, or a fixture.

## 3. Data model

```swift
struct Meeting: Identifiable, Hashable, Sendable, Codable {
    /// eventIdentifier + start timestamp — recurring events share an
    /// eventIdentifier, so the occurrence start is part of the id.
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
    var calendarTitle: String
    var calendarColor: RGBA              // no AppKit types in JoinCore
    var location: String?
    var notes: String?
    var url: URL?
    var myStatus: ParticipationStatus    // accepted (also organized events, and events without attendees on calendars you can edit), tentative, declined, unknown (not answered, not invited, or someone else's calendar)
    var hasParticipants: Bool            // someone other than you is on it (§4); false for focus time and reminders to yourself
    var joinURL: URL?                    // filled by MeetingLinkDetector
    var isOutOfOffice: Bool              // filled by OutOfOfficeDetector (§9a)
}

enum AlertState: Equatable {
    case pending                 // will fire at start - leadTime
    case snoozed(until: Date)
    case showing
    case dismissed               // no more alerts for this occurrence
}

enum PauseState: Codable {       // set from the panel's bell menu
    case active
    case until(Date)             // "1 hour", "until tomorrow"
    case indefinitely            // "until I resume"
}

enum EventVisibility: String, Codable, CaseIterable, Comparable {   // stored as its raw value (§4)
    case showAndAlert            // "Show and alert": like any other event
    case listOnly                // "Show in the list only": the panel's lists, nothing else
    case exclude                 // "Exclude": left out everywhere; exclude < listOnly < showAndAlert
}

final class Preferences {                  // @Observable, persisted in UserDefaults
    var leadTime: TimeInterval = 180       // always whole minutes; kept while Alert me is Never
    var fullScreenAlertsEnabled = true     // false = Alert me › Never: no full-screen alerts (§5)
    var snoozeDurations: [TimeInterval] = [60, 300]   // exactly two
    var alertScreens: AlertScreens = .all  // .all, .main, .secondary, .pointer (§6)
    var autoCloseEnabled = true
    var autoCloseAfter: TimeInterval = 15 * 60
    var soundName: String? = nil
    var soundRepeats = false
    var enabledCalendarIDs: Set<String>?   // nil = never chosen → all
    var eventsWithoutParticipants: EventVisibility = .showAndAlert   // §4
    var menuBarShowsNextEvent = true
    var menuBarShowsEventTitles = false
    var outOfOfficeEvents: EventVisibility = .listOnly   // §4, §9a
    var outOfOfficeKeywords: [String]
    var appearance: AlertAppearance
    var customAppearance: AlertAppearance?   // the Custom style card's look (§8); nil until there's one
    var startingSoonPill: StartingSoonPill
    var panelListFilter: PanelListFilter = .week   // the panel's Today | 7 Days switch
    var checksForUpdates = true            // the daily update check (§14); Check Now works either way
    var lastUpdateCheck: Date?             // the last successful check; nil = never
    var offeredUpdateVersion: String?      // the version the last successful check offered; nil = none
    var unsupportedUpdate: UnsupportedUpdate?   // a release this macOS can't run; nil = none
}

struct UnsupportedUpdate: Codable, Equatable {  // saved as JSON: {"version":"2.0.0","minimumSystem":"15.0"}
    let version: String               // the release Install found this Mac can't run (§14)
    let minimumSystem: String         // its LSMinimumSystemVersion
}

struct StartingSoonPill: Codable, Hashable {  // saved as JSON; missing keys fall back to the default
    var minutes = 5                   // 1...60; when the menu bar pill and the panel's starting-soon card appear
    var fill: RGBA?                   // nil = the system accent color
    var text: RGBA?                   // nil = Automatic: white unless the fill shown gives it < 3:1, then near-black;
                                      //   Settings no longer sets it, only shows one an earlier build stored
}

struct AlertAppearance: Codable, Hashable {   // saved as JSON with "version": 3
    var blurMode: BlurMode            // .dark, .light (.none only from old saves)
    var tint: RGBA?                   // nil = no tint
    var tintStrength: Double          // 0...1, kept while the tint is off
    var textColor: RGBA?              // nil = Automatic (Settings' Event text)
    var join: AlertButtonColors
    var dismissAndSnooze: AlertButtonColors
    static let `default` = AlertAppearancePreset.dark.appearance
}

struct AlertButtonColors: Codable, Hashable {
    var text: RGBA?                   // nil = Automatic; only an earlier build stores one (a legacy Text row, §8)
    var fill: RGBA?                   // nil = Automatic (Orange for Join)
    var fillOpacity: Double           // scales the fill; Join 0.4...1 (Settings sets 1), others 0...1
}
```

Launch at login is not a preference: it is read from and written to `SMAppService` directly. The pause state is stored by `AlertCoordinator` next to the alert states (§5). The time of the last failed update check isn't stored at all: `UpdateChecker` keeps it in memory (§14). Setting `offeredUpdateVersion` or `unsupportedUpdate` to nil removes its key, and JSON that can't be read loads as nil. Fixture runs keep `lastUpdateCheck`, `offeredUpdateVersion` and `unsupportedUpdate` in memory too, unless `JOIN_FIXTURE_UPDATE=live` (§12).

`RGBA` is a small Codable sRGB struct, so calendar colors and the theme round-trip to JSON. It also holds the color math the appearance needs: hex parsing, compositing (`composited(over:)`, `mixed(with:amount:)`), WCAG relative luminance and contrast ratio, and `mostLegible(of:_:)`.

## 4. Calendar integration (EventKit)

**Permission.** `EKEventStore.requestFullAccessToEvents()` (macOS 14 API). `Info.plist` needs `NSCalendarsFullAccessUsageDescription`. Entitlement `com.apple.security.personal-information.calendars` if sandboxed (recommended; nothing here needs to escape the sandbox).

**Calendars.** `store.calendars(for: .event)` grouped by `calendar.source.title` (e.g. a work account and a personal account appear as separate groups). Calendar colors are converted to a Codable `RGBA` so `Meeting` stays free of AppKit types. The Calendars pane (§8) writes `Preferences.enabledCalendarIDs`.

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
- `hasParticipants` is true when someone other than you is on the event: an attendee whose `isCurrentUser` is false, or an organizer who isn't you. A booked room or resource doesn't count. An event with nobody else on it (no attendees and no organizer, or only you and rooms) has no participants: focus blocks, reminders and holds you made for yourself, and most holiday and subscribed calendar blocks. Such events are still mapped; `MeetingStore` decides whether they're used.

After fetching, `MeetingStore` fills `joinURL` (§9) and `isOutOfOffice` (§9a) on each meeting, then filters them (below). The order matters: the filter reads `isOutOfOffice`.

**Which events are used.** Settings › General › Events (§8) has a choice, an `EventVisibility`, for each of two kinds of event: events with no participants (`Preferences.eventsWithoutParticipants`, **Show and alert** by default) and out-of-office events (`Preferences.outOfOfficeEvents`, §9a, **Show in the list only** by default). `MeetingFilter.visibility(of:eventsWithoutParticipants:outOfOfficeEvents:)` (JoinCore) gives a meeting's choice: the one for its kind; for an event of both kinds, the one that shows less (`min`, since `exclude < listOnly < showAndAlert`); and `.showAndAlert` for any other event. `MeetingStore.meetings` keeps the visible ones (`MeetingFilter.visible`: the choice isn't Exclude) and `alertableMeetings` the alertable ones (`MeetingFilter.alertable`: the choice is Show and alert), always a subset. Everything reads from those two:

| Choice | Panel lists | Hero card, menu bar item, full-screen alert |
|---|---|---|
| Show and alert | yes | yes |
| Show in the list only | yes | no |
| Exclude | no | no |

So Exclude leaves an event out everywhere, as if its calendar were unchecked but decided per event. Out-of-office rows stay striped and muted whatever the choice (§7); an event with no participants is drawn like any other row, with its Join or Directions button. The defaults keep what 1.1 did out of the box. Changing either choice refetches (below), so excluded events come back as soon as they're shown again.

**Staying fresh.** Refetch on:

- `NSNotification.Name.EKEventStoreChanged` (fires when the system calendar database changes, including after a Google sync),
- `NSWorkspace.didWakeNotification`,
- a change to `enabledCalendarIDs`, `eventsWithoutParticipants`, `outOfOfficeEvents` or `outOfOfficeKeywords`,
- **Refresh Calendars** in Settings,
- a 15-minute safety-net timer.

Each refetch replaces `MeetingStore.meetings`, records `lastRefreshed` (for the "Updated just now" label in Settings) and asks `AlertCoordinator` to re-plan. Google sync latency itself is governed by Calendar.app › Settings › Accounts › Refresh Calendars; the README tells users to set it to "Every minute" or "Every 5 minutes".

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
                         leadTime: TimeInterval,
                         isPaused: Bool,
                         now: Date) -> AlertPlan?
}
```

Rules:

1. For each meeting with state `.pending`: `fireAt = start − leadTime`. If `fireAt < now` but `end > now` (we missed it: app launched late, Mac was asleep) → fire **now**, unless the meeting already started more than 5 minutes ago (`lateAlertGrace`), in which case it is skipped: alerting for a meeting you are presumably already in is noise.
2. `.snoozed(until)` → `fireAt = until`, again clamped to `now` if in the past, and dropped once `end < now`.
3. `.showing` and `.dismissed` produce nothing.
4. Meetings whose `fireAt` fall within 1 second of the earliest one are grouped into a single `AlertPlan`, so two back-to-back meetings produce one alert listing both instead of two stacked windows.
5. If `isPaused`, return nil. `AlertCoordinator` passes true while full-screen alerts are paused (`PauseState.isPaused(at: now)`) or turned off (**Alert me** set to **Never**, `Preferences.fullScreenAlertsEnabled` false). When a pause ends, or a time is picked again after Never, rule 1 applies as usual: a meeting that is about to start, or started less than 5 minutes ago, alerts right away.

The meetings passed in are `MeetingStore.alertableMeetings`: those whose Events choice is Show and alert (§4).

`AlertCoordinator` (side effects):

- Holds one `DispatchSourceTimer`. On every re-plan it cancels and re-arms the timer for `plan.fireAt`, with 0.5 s leeway.
- Also runs a 30-second **heartbeat** that re-plans and fires anything overdue. This catches the cases where a one-shot timer silently fails: system sleep, clock/timezone change, the process being suspended by App Nap (which we also disable via `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` while an alert is pending within 5 minutes). The heartbeat is also what ends an expired timed pause.
- Schedules nothing until `start()` is called. Fixture runs (§12) never call it, so they can't alert.
- On fire: mark meetings `.showing`, ask `AlertWindowController` to present on the screens chosen in `Preferences.alertScreens`, play the sound, start the auto-close timer if configured.
- User actions from the alert: Dismiss → `.dismissed`; Snooze(d) → `.snoozed(until: now + d)`; **At \<time\>** → `.snoozed(until: start)`, or `.dismissed` if the meeting has already started; Join → open URL then `.dismissed`.
- `AlertState`s are persisted (`UserDefaults`, each with the meeting's end as expiry, pruned when expired) so a relaunch during a snooze doesn't re-alert or lose the snooze.
- **Pause.** `pause(_ option: PauseOption)` turns "1 hour", "until tomorrow" (local midnight) or "until I resume" into a `PauseState`; `resume()` sets `.active`. The state is saved as JSON under `pauseState`, so "Pause until tomorrow" survives a relaunch. A timed pause that has run out collapses to `.active` on load and on the next re-plan.
- **Never.** `AlertCoordinator` re-plans when `fullScreenAlertsEnabled` changes, as it does for the lead time. Never is modelled as its own Bool, not a lead time, so `leadTime` keeps the last time chosen and the scheduler stays unaware of it beyond `isPaused` (rule 5). Picking Never cancels what's pending: nothing fires, snoozed alerts included, until a time is picked again. An alert already on screen stays until it's closed, since re-planning waits while one shows (below); the lead chose this, for least surprise. The menu bar item, its starting-soon pill and the panel don't depend on it, and the menu bar doesn't show the paused bell.
- One alert at a time: while an alert is on screen, nothing else fires; the next plan is computed when it closes.
- If a meeting is edited (start moves) its `id` changes → new occurrence, state resets to `.pending`. Cancelled meetings disappear from the store; if their alert is showing, the window closes.
- `showDemoAlert()` presents a fake meeting starting 3 minutes out (on a whole second, so the countdown starts at 3:00), "Hello, I’m a demo event" (`MenuBarPresenter.demoEventTitle`), for **Show Demo** on the Full-Screen Alert and Appearance panes. It works while paused and with **Alert me** set to **Never**. Its buttons only close it. It is refused, and the Settings button is disabled, while a real alert is on screen (`isAlerting`); a real alert that fires during a demo replaces it.
- `willPresentAlert` runs right before any alert (real or demo) is presented. The app uses it to close the menu bar panel, including a header menu that is open, so the panel can't take keyboard focus back from the alert.

## 6. Alert window (AppKit)

One `AlertWindow` (an `NSPanel`) per target screen. `Preferences.alertScreens` picks them, through `AlertScreens.targetIndices(screenCount:pointerScreenIndex:)` in JoinCore, a pure function over indices into `NSScreen.screens`; `AlertWindowController.targetScreens(for:)` hands it the screen count and the index of the screen under the mouse pointer, and maps the indices it returns back to screens. Index 0 is the main screen: the one with the menu bar, which macOS calls the main display (`NSScreen.screens.first`). `.all` covers every screen, `.main` the main one, `.secondary` (new in 1.2.0) every other one, and `.pointer` the one under the pointer when the alert fires. The alert never silently vanishes: with a single screen `.secondary` falls back to the main one, and so does `.pointer` when the pointer is on no screen. Before 1.2.0, `.main` was `NSScreen.main`, the screen with the key window, which can be a secondary one while Join!'s Settings window sits there, and `.pointer` fell back to it. The first window becomes key and the others are ordered front. The windows are recreated on `NSApplication.didChangeScreenParametersNotification` (display hot-plug while showing), so unplugging the last secondary screen moves a Secondary screen only alert to the main one.

```swift
let panel = NSPanel(contentRect: screen.frame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
panel.level = .screenSaver                        // above menu bar and full-screen apps
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.becomesKeyOnlyIfNeeded = false
panel.isOpaque = false
panel.backgroundColor = .clear
panel.contentView = FirstMouseHostingView(rootView: AlertRootView(session: session))
panel.makeKeyAndOrderFront(nil)                   // no NSApp.activate
```

**Why a non-activating panel.** Since macOS 14, a background app can't make itself the active app (cooperative activation), so an ordinary window plus `NSApp.activate` showed the alert but left the keyboard with whatever app the user was in. A `.nonactivatingPanel` becomes the key window without activating Join!: the user's app stays frontmost, the alert gets the keystrokes, and when it closes focus is simply back where it was.

**Keys.** An `NSEvent` local monitor, installed while an alert is presented and removed on dismiss, handles `Esc` (dismiss) and `Return` / keypad `Enter` (join, when a link exists) for events targeting one of the alert panels. Key auto-repeats, and keys pressed within 0.75 s of the alert appearing (`keyArmingDelay`, measured against each event's own timestamp), are swallowed so a keystroke the user was already typing or holding in another app can't dismiss the alert or join a call. After that, other keys pass through to the alert's views so Full Keyboard Access still works. SwiftUI `keyboardShortcut`s aren't used: they depend on the responder chain and silently did nothing in a borderless window. `FirstMouseHostingView` accepts the first click, so buttons on a secondary display's panel work without a focusing click. Only the first panel is made key; the others mirror the content.

**Backdrop.** `AlertBackdrop` (SwiftUI) stacks, bottom to top: an `NSVisualEffectView` (`material: .fullScreenUI`, `blendingMode: .behindWindow`) whose `appearance` is forced to `.darkAqua` / `.aqua` for the dark/light blur modes (left out for `.none`); the tint color at `tintStrength`; and a radial scrim behind the content (black at 32 % on dark backdrops, white at 50 % on light ones) that keeps text legible over busy wallpapers.

**Layout.** `AlertContentView` is shared by the alert and the Settings preview. A `TimelineView(.periodic(from:by: 1))` anchored on a whole second drives it, so the countdown steps evenly; the preview passes a frozen `now` instead. Top to bottom, centered:

1. The calendar: a dot in the calendar's color and its name.
2. The countdown, colored by phase (below).
3. The title, 52 pt bold, up to two lines.
4. The time range (clock icon) and the location (pin), side by side, or stacked when they don't fit. The location is left out when it is only the join link again.
5. **Join**, when a link exists: a wide button with a video icon, "Join" before the start and "Join now" after, and a `↩` key hint.
6. The snooze row: a "Snooze" label, one button per snooze duration ("1 min", "5 min", "1 hr", worded like Settings), each duration once (`AlertCountdown.snoozeChoices`: when both snooze buttons in Settings read the same, the alert, the demo and the Settings preview show one button, not two identical ones), and **At event start**, which snoozes until the meeting starts (VoiceOver: "Snooze until the event starts at 2:00 PM"). It is left out once the start has passed. The design's "At 2:00 PM" was renamed at the user's request.
7. **Dismiss**, with an `esc` key hint.

When several meetings share one plan, each gets its own calendar, countdown, title and details block (titles at 40 pt), above a single button group; the Join button names the meeting it joins ("Join Design Sync"). If the blocks don't fit the screen they scroll, with a fade at the edges, while the button group keeps its place, so Join, snooze and Dismiss always stay reachable. The hosting view has no sizing constraints, so the alert never grows past a small screen. A demo adds the line "This is a demo full-screen alert. Press Esc to close it."

**Countdown.** `AlertCountdown` (JoinCore) turns `(start, end, now)` into a phase and its text. Colors come from `AlertPalette.countdownColor(for:)`: brighter on dark backdrops, deeper on light ones.

| Phase | When | Text | Color (dark / light backdrop) |
|---|---|---|---|
| before | before the start | "Starts in 2:59", "Starts in 1:05:00" (rounded up, so never "0:00" early) | amber `#FFB340` / `#A84B00` |
| starting | the first minute after the start | "Starting now" | orange `#FF9F0A` / `#A13A00` |
| started | after that | "Started 3 min ago", "Started 1 hr 5 min ago" | red `#FF6961` / `#C1121F` |
| ended | after the end | "Ended" | red |

It also builds the Join title, the snooze labels and their VoiceOver labels ("Snooze 5 minutes", "Snooze until 2:00 PM").

**Appearance and palette.** `AlertAppearance` (§3) stores only what the user chose; a `nil` color means Automatic. The views never pick colors themselves. They read `appearance.palette`, an `AlertPalette` of concrete colors:

- `surface`: an opaque stand-in for the blurred backdrop, `#26262B` for dark blur or `#ECECF0` for light, mixed with the tint at its strength.
- `text`: the custom color, or white / `#1D1D1F`, whichever contrasts more with the surface. That choice also sets `isDark`, which picks the countdown colors, the scrim and the automatic button fill.
- Join: the fill defaults to amber `#F5A524`, which Settings names Orange. The automatic label is white or near-black, whichever reads better on the fill.
- Snooze & Dismiss: the automatic fill is white at 16 % on a dark backdrop and black at 7 % on a light one. The automatic label is chosen by contrast, like Join's.
- Each button kind's fill opacity scales its fill, automatic or custom. Join's is limited to 40–100 % so the main action never disappears; Snooze & Dismiss goes from 0 to 100 %. Settings sets Join's to 100 % (only a look saved by an earlier build has less), and the Snooze & Dismiss buttons' through their swatches (22 %) or the opacity in their Other… well.
- `material`: the layer the blur adds over the desktop. Only the Settings preview draws it, because a window can't blur what is behind it inside itself.

`contrastWarnings` checks the event text, the Join label and the Snooze & Dismiss labels against their composited backgrounds. Each one under 4.5:1 (WCAG AA for body text) gets a warning with its ratio, rounded down so 4.46 reads "4.4:1", never "4.5:1", and the Colors row it shows directly under in Settings (`AlertContrastWarning.row`, §8). Every warning, the menu bar pill's too (§8), uses one template, `AlertContrastWarning.message(subject:ratio:advice:)`: "Event text may be hard to read (3.2:1)." and then advice that names the fix or what to try instead:

| Cause | Advice | Shown under |
|---|---|---|
| Event text on Other… | "Aim for 4.5:1, or choose Automatic." | Event text |
| Automatic event text on a tint | "Try a different tint strength." | Tint (below Strength) |
| The Join button, with a legacy label color | "Aim for 4.5:1, or set its Text to Automatic." | Join button |
| The Join button, otherwise | "Try another color." | Join button |
| Snooze and Dismiss, with a legacy label color | "Aim for 4.5:1, or set their Text to Automatic." | Snooze & Dismiss buttons |
| Snooze and Dismiss, on a swatch over a tint | "Try a different tint strength." | Snooze & Dismiss buttons |
| Snooze and Dismiss, otherwise | "Try another color." | Snooze & Dismiss buttons |

Automatic text on an untinted backdrop always reads, and every Join and Snooze & Dismiss swatch reads on every preset (tested), so no preset warns, and picking a button swatch on one doesn't either.

Presets (`AlertAppearancePreset`):

| Preset | Backdrop | Tint | Join | Snooze & Dismiss |
|---|---|---|---|---|
| Dark (default) | dark blur | none | amber, automatic label | automatic |
| Light | light blur | none | amber, automatic label | automatic |
| High contrast | dark blur | black at 70 % | `#FFD60A`, automatic label (near-black; black until 1.2.0) | white at 22 % |
| Midnight | dark blur | `#1E3A8A` at 45 % | `#2563EB`, automatic label | automatic |

`matchingPreset` compares appearances the way a person sees them (`isEquivalent`): the same backdrop and the same resolved palette (surface, text, Join label and fill, button label and fill) at 8 bits, alpha included. What's stored doesn't count, so a custom color equal to the automatic one, or a tint strength while there's no tint, changes nothing. Matching never rewrites what's stored: switching a pop-up to Other… starts from the color currently shown, so (Tint from None aside, §8) nothing changes until the user picks a new one, and normalizing that color to Automatic would snap the pop-up straight back. `style` (`AlertStyle`: a preset, or `.custom` while none matches) is the Style card Settings outlines, and `swatch` draws the Custom card's miniature like the presets'. The Snooze & Dismiss fill converts its opacity in both directions between Automatic and a color, so switching back and forth keeps the look. `isDefault`, which disables Restore Defaults, is stricter than matching Dark: there must also be no tint, and no stored event text color, label color or Snooze & Dismiss fill, so a legacy Text row, or Tint, Event text or Snooze & Dismiss left on Other…, keeps the button enabled even when the look matches Dark. Join's Other… stores its default Orange, which `isDefault` doesn't check (the alert shows Orange either way), so the Join button on Other… at Orange still counts as the default.

**Saved format.** The appearance is encoded as JSON with `"version": 3` since 1.2.0's swatches; missing keys fall back to the default. Version 2 has the same shape, and older builds still read version 3. Version 2 and JSON without a version (below) are migrated on load, in this order: a look that matches a preset, by today's definition or an earlier build's (High contrast with its black Join label), becomes that preset exactly, so no High contrast user gets a stray Text row; then an automatic button fill below 100 %, which Settings can no longer show now that Fill opacity is gone, becomes Other… at the same visible alpha: Join's default Orange at its opacity, and for Snooze & Dismiss the automatic white or black at exactly its opacity times the automatic 16 % or 7 %, unrounded, unlike `setButtonFillCustom`'s whole percents, so no look of the user's own rounds into a preset's; custom label colors stay, each on its legacy Text row. Version 3 loads as saved. JSON without a version is the shape saved before the redesign, where every color was explicit (`textColor`, `backgroundTint` + `backgroundOpacity`, `button*` and `primary*` colors and opacities). An untouched old default becomes the new default. Anything customized keeps its exact colors: the background tint and opacity become `tint` and `tintStrength`, the primary button becomes Join (opacity clamped to 40–100 %), and the other buttons become Snooze & Dismiss. An old "No blur" survives, and only then does Settings offer it as a third Backdrop segment (`backdropChoices`).

## 7. Menu bar

`StatusItemController` owns an `NSStatusItem` and a `MenuBarPanelWindow`. SwiftUI's `MenuBarExtra` was used first and dropped: its window grows with its content but never shrinks, and it can't be closed programmatically. An `NSPopover` replaced it until the redesign, which called for a borderless panel with its own corners and material and no arrow. SwiftUI still requires one scene, so `JoinApp` declares a `MenuBarExtra` with `isInserted: .constant(false)`, which keeps SwiftUI's standard Edit menu (copy and paste in text fields) without adding UI.

**Status item.** `MenuBarPresenter.status(...)` (JoinCore) returns a `MenuBarStatus`: a kind, optional text and an accessibility label. Its inputs are the alertable meetings (only events whose Events choice is Show and alert, §4), `now`, the `PauseState`, `menuBarShowsNextEvent`, `menuBarShowsEventTitles` and the starting-soon window (`startingSoonPill.window`, 5 minutes by default). Precedence: paused > starting soon > in a meeting > within the hour > later, among the meetings `MenuBarPresenter.focus` keeps: a Maybe or unanswered meeting already in progress steps aside while a meeting you're attending (accepted, your own on a calendar you can edit, or organized by you) overlaps it and is on now or starts within the hour. So a long Maybe block in progress gives way to the call you accepted inside it ("Next in 47 min", not "4 h 17 min left") and comes back when nothing you've accepted is that close. Before it starts, a Maybe or unanswered meeting counts like any other, since its alert fires (a Maybe call inside an accepted meeting still gets its pill), and one that clashes with nothing you've accepted keeps its pill, ring and card. The user asked for this, after In Your Face; declined events never get this far, since the calendar service drops them.

| Kind | When | Drawn as |
|---|---|---|
| idle | nothing upcoming in the 7-day window | `calendar` symbol alone |
| later | next meeting more than an hour away | `calendar` + a countdown later today ("Next in 11 h 40 min"), otherwise the day and time: "Tomorrow at 1:00 PM", "In 3 days at 9:10 AM" (calendar days). The user chose this over the design's "1:00 PM" / "Tomorrow 1:00 PM" / weekday. VoiceOver: "in 11 hours 40 minutes, at 1:00 PM", "tomorrow at 1:00 PM", "in 3 days, Thursday at 9:10 AM" |
| withinHour | next meeting within the hour | `calendar` + "Next in 42 min" |
| startingSoon | next meeting within the starting-soon window (5 minutes unless changed in Settings › General › Menu bar › Starting soon) | a filled pill (the system accent unless changed in Settings › General › Menu bar › Color) with a `video.fill` icon + "Next in 4 min"; the label is white, or near-black when white is under 3:1 on the fill (the orange, yellow and green accents), unless an earlier build stored a text color |
| inMeeting | in a meeting (the one that started most recently) | a 16 pt ring that drains from full to empty over the meeting + "40 min left" |
| paused | full-screen alerts paused | `bell.slash` alone, never text. **Alert me** set to **Never** isn't a pause: the item keeps counting down |

- Starting soon wins over a meeting in progress, so the next call shows while you are still in the previous one.
- Durations are whole minutes rounded up, so "0 min" never shows before a start. Time left beyond an hour reads "2 h 15 min".
- Settings › General › Menu bar › **Shows** picks one of three (`MenuBarDisplay`, stored as `menuBarShowsNextEvent` and `menuBarShowsEventTitles`): **Icon only**, **Time until next event** (the default), or **Title and time until next event**. Without a title a countdown starts with "Next" ("Next in 42 min"); with one, the title takes its place, truncated to 24 characters: "Product Planning · in 4 min".
- With **Icon only**, the item has no text but keeps its state icon (pill, ring, bell).
- Plain states use template images, so the menu bar tints them. The pill is drawn in full color, and redrawn when the system colors change. Text uses a monospaced-digit font, and countdowns past an hour always show two-digit minutes ("11 h 05 min", "2 h 00 min left", `MenuBarPresenter.steadyDuration`), so the item keeps its width as the minutes tick instead of nudging every other menu bar item each hour. The panel keeps the shorter "2 h".
- The button re-renders through observation tracking whenever `AppModel.menuBarStatus` or the pill's settings (`Preferences.startingSoonPill`) change, and when the system colors change. `AppModel.now` ticks on every :00 and :30 of the clock, so countdowns stay in step with meetings, which start on whole minutes.
- VoiceOver reads full words: "Join!: Product Planning starts in 4 minutes", or "Join!: full-screen alerts paused".

**Panel window.** `MenuBarPanelWindow` is a borderless, non-activating `NSPanel` at `.statusBar` level, 368 pt wide, on all Spaces. Like the alert, it takes Esc and Return without pulling the user's app out of the foreground. Its background is the system menus' material with a frost over it (below). On macOS 26 and later it's an `NSGlassEffectView` (Liquid Glass, 14 pt corners), looked up at runtime because the SDK the app builds against predates it, and set up only through its public `style` (pinned to regular, which adapts the backdrop's luminance; clear doesn't), `cornerRadius` and `contentView`. Before macOS 26 it's an `NSVisualEffectView` with the `.menu` material and a rounded mask image, which shapes both the blur and the window shadow. The glass sits in a layer-backed view clipped to the same continuous rounded rectangle: unclipped, the glass gave the window a square shadow, a dark outline with darkened corners around the rounded panel. **Frost.** Bare glass let the backdrop's brightness through: over a white window, dark-mode glass settles at mid-gray, where even pure white text only reaches about 4.3:1, and the old grays (tuned for a solid panel) measured 1–2:1 on the user's screenshots. So `MenuBarPanelView` lays a frost between the glass and the content, `#1E1E20` (dark) or `#FAFAFC` (light) at 50%: text sits on a steadier surface, while half of the glass (the wallpaper's color, its depth and edge) still shows. The canvas recommended 70%, which kept more contrast margin; the user chose 50% on screen. It's 88% with Increase Contrast, opaque with Reduce Transparency, and 40% over the pre-macOS 26 menu blur, which is already thick. The design canvas compared this with a glass rim around a solid sheet, tiles per section, and a glass header over a content floor; the user chose the frost. The `panelFrost` hook (§12) tries other opacities on the real panel. The SwiftUI view sits in an `NSHostingView` that accepts the first click.

**Sizing.** `MenuBarPanelView` measures its header and its body with `GeometryReader` preferences and reports the sum through `MenuBarPanelContext`. The controller hangs the panel 6 pt below the status item with the top edge fixed, and sets the height to that natural height, capped at 640 pt and at the room left above the bottom of the screen (minus an 8 pt margin). The x position follows the item and is nudged to stay on screen. It's set when the panel opens; while it's open only the height follows the content, because the item changes width with its text (pausing shrinks it to a bell) and the panel would jump sideways with it. The resize runs on the next run-loop turn, because resizing the window from inside a SwiftUI layout pass re-enters layout. When the content is taller than the panel, the body scrolls and a 32 pt fade at the bottom shows there is more. It fades into the frost and only down to 40%, so the last row stays legible, and its strength follows how much is still hidden, so it is gone at the end of the list. The Today | 7 Days switch changes the height too: the list snaps to its new length and the window follows in one step; only the switch's thumb slides.

**Closing and keys.** The panel closes on Esc, ⌘W, a second click on the item, a click anywhere else (global and local event monitors), the app resigning active, another window becoming key (except while one of the panel's own menus is open), a Space change and a display change. It also closes before Join, Directions, Settings or Open System Settings open anything, and before any alert appears. ⌘, opens Settings and ⌘Q quits. ⌘1 and ⌘2 pick Today or 7 Days, matched by key (the number row's and the keypad's) so they also work on layouts like AZERTY; the thumb slides as for a click. When that half can't be picked (the switch is hidden, or nothing is left today) the panel beeps. Return runs the hero card's button when the hero is Starting soon or Now.

**Panel content.** `PanelPresenter.content(meetings:alertable:now:startingSoonWindow:)` (JoinCore) returns one hero card and a list of sections. It lists exactly the meetings it's given, `MeetingStore.meetings` (the visible ones, §4); before 1.2.0 it also took `showsOutOfOffice:` to drop out-of-office rows, which the Exclude choice now does upstream. The views draw them with `PanelColors`, resolved from `PanelPalette` (JoinCore) for the drawing appearance and Increase Contrast: five inks (primary, strong, secondary, tertiary, warning) instead of ten grays, and fills as fixed opacities of black or white that match the system fills. The inks stay fixed sRGB, not vibrant: AppKit only gives vibrancy to SwiftUI's hierarchical styles, which can't be held to a contrast, and even vibrant white can't reach 4.5:1 on bare glass over a white window. `PanelPaletteTests` checks every ink at 4.5:1 on the frost over the lightest dark glass and the darkest light glass measured on the user's screenshots (`#7A7A7A` over a white window, `#8D8E8F` over a dark one; a brighter or darker backdrop can dip below that at 50%), on the hero card and the out-of-office stripes, and, for every system accent, on the starting-soon card and on the prominent button at rest and under the pointer. The prominent button is solved per accent (`PanelPalette.accentButton`): the accent darkened 15% (20% in dark mode), since white on the plain default blue is under 4.5:1; the better of white and near-black as the label (near-black on yellow, orange, green); the fill stepped further from the label until it reads at 4.5:1; and a hover fill that moves further the same way, so pointing can only raise the contrast. The starting-soon card is the regular card with the accent tint over it: 12% in light mode, and in dark mode up to 10%, less for bright accents (down to none for yellow), until its text keeps 4.5:1 (the accent border still marks it). "Starts in 4 min" is the accent stepped toward white or black until it reads at 4.6:1 on that card. Cards (hero, nothing-today, paused bar, update bar, permission prompt) are white at 55% in light mode, away from the dark text, and white at 6% in dark mode, with a separator edge. With Increase Contrast the inks go further toward black or white, the separators get stronger, and the filled buttons, the active header button and the switch get a 3:1 edge (the switch's thumb edge is drawn 1 pt wide).

- **Header:** today's date ("Tuesday, 6 October", localized), a "Fixture" badge in fixture runs (§12), the bell button and the gear menu. The panel window's accessible name is "Join! meetings".
- **Paused bar**, while paused: "Full-screen alerts paused until 11:50 AM", "… until tomorrow" or "Full-screen alerts paused", with **Resume**.
- **Update bar** (`UpdateBar`, §14), while an update is available or being installed: the paused bar's card, paddings and button style with an `arrow.down.circle` icon, below the paused bar when both show. It reads "Join! 1.1.0 is available" with **Install** (disabled while a check runs), then "Downloading Join! 1.1.0… 45%" (no percent while the size is unknown) and "Installing Join! 1.1.0…" with no button. If Join! can't replace itself it reads "Quit Join!, then move Join! 1.1.0 to Applications" with **Show in Finder**; if the copy is gone by the time that's clicked (the user already moved it), the bar goes back to **Install**. If the install fails, it reads "Couldn't install Join! 1.1.0" with **Download Page**, and the button's tooltip says why (`UpdateCopy.failureReason`). When Install finds that the release needs a newer macOS, the bar goes away and Settings says "Join! 2.0.0 needs macOS 15.0 or later" (§14). A failed check never shows here, only in Settings. The words come from `UpdateCopy` (JoinCore).
- **Hero**, exactly one, chosen from the alertable meetings the way the status item chooses (`MenuBarPresenter.focus`: a Maybe or unanswered meeting in progress steps aside for one you're attending inside it):
  - **Starting soon**, when the next start is within the starting-soon window, the same as the menu bar pill's (5 minutes by default): accent-tinted card, "Starts in 4 min", accent button. Wins over Now.
  - **Now**, the meeting you are in: "Now · 40 min left", a progress bar in the calendar color, accent button.
  - **Next**, the next meeting later today: neutral card, "Next · in 2 h 15 min", neutral button.
  - **No more meetings today**, with "Next up tomorrow at 1:00 PM, in 15 h 30 min" (the countdown is dropped a day or more ahead) or "Nothing in the next 7 days".
  - Meeting cards show the label, the time range, the title with a calendar-color dot, the short location and any overlap (for meetings that haven't started), and the action button.
- **Sections** below the hero list the visible meetings (§4), Show in the list only ones included, leaving out anything that has ended:
  - **Now** (titled **Also now** when the hero is a Now card): other ongoing meetings, out-of-office blocks included.
  - **Upcoming events**, one heading over everything that hasn't started, after In Your Face. Under it, today's meetings yet to start, the hero's included (the user chose this over the design's "Later today", which left the hero's meeting out; the next meeting shows twice), then one group per following day in the 7-day window. In **7 Days** each group gets a day heading (`PanelDayHeading`: **Today**, **Tomorrow** Wed 7 Oct, **Thursday** 8 Oct, localized), quieter than the list headings and followed by a hairline, so the days read as parts of one list. Type scale (option B of the panel typography canvas, the user's pick): list headings ("Now", "Also now", "Upcoming events") 15 pt bold in `primary`; day headings 10.5 pt small caps (`textCase(.uppercase)`, 0.7 pt tracking), semibold `secondary` with the date in medium `tertiary`; meeting titles 13 pt semibold; start times 12 pt medium `strong` over regular `tertiary` end times; the switch's chosen half semibold. The panel's grays differ little in dark mode (both sit at the 4.5:1 floor), so the levels come from size, weight, case and spacing rather than color. In **Today**, or when nothing comes after today, there is only one day, so its rows sit under Upcoming events with no day heading (`PanelFilterState.showsDayHeadings`). The model keeps these as `PanelSection`s of kind `.now`, `.today` and `.later`.
- **Today | 7 Days switch**, centered 10 pt under the hero card, scrolling with it: a 144 × 24 pt track with a thumb under the choice, no accent color. **Today** lists Now and today's upcoming meetings; **7 Days** adds the following days, which is the whole list. The choice is remembered (`Preferences.panelListFilter`, 7 Days by default) and only affects the list: the hero card, Return, the menu bar item and alerts ignore it. `PanelContent.filtered(by:)` (JoinCore) decides:
  - The switch hides when nothing comes after today, since both halves would list the same rows.
  - When nothing is left today but out-of-office blocks (evenings, the day's last meeting), Today is dimmed and the week shows; the stored choice is kept, so Today comes back the next morning. The original app's Today showed an empty list here. Clicking 7 Days then makes it the choice.
  - Today's sections always lead the week's, so switching keeps Now and the Upcoming events heading in place: 7 Days adds the Today day heading above today's rows (they move down by its height, a choice the user made) and the following days below them.
  - It's drawn by hand, not with a segmented `Picker`, which draws pre-Tahoe chrome when built against this SDK and loses its labels in snapshots. VoiceOver reads a "Show meetings" group of two buttons, the chosen one selected and a dimmed Today unavailable, with the hint "Nothing else today"; the others' hints are "Command-1" and "Command-2". Tooltips name the shortcuts too.
- **Rows:** start over end time, a calendar-color bar, the title, at most one detail line, and an icon button. The detail is, in this order: a progress bar with "3 h 10 min left" for a running meeting, an amber "Overlaps Workshop", or a pin with the short location.
- **Out-of-office rows** are striped and muted, with no detail and no button, whichever Events choice lists them. An event with no participants on Show in the list only is an ordinary row.
- **Hover.** The panel's own controls behave the same under the pointer: the header's bell (paused or not) and gear, the hero card's button, **Resume**, the update bar's button, the switch's unchosen half and the row icons brighten their fill (0.12 s ease, none with Reduce Motion) and show the pointing-hand cursor. They share `panelHover(_:)`, which sets the cursor on every move because AppKit resets it as the pointer crosses the hosting view. The calendar-permission prompt keeps standard system buttons, which don't change the cursor.
- **Overlaps.** A meeting that starts while an earlier one is still running is flagged with the latest-ending of those. Only the later meeting of a pair is flagged, and out-of-office blocks never count. On a card the warning also says until when: "Overlaps Workshop, which runs until 7:30 PM".
- **Actions.** Join (video icon) when a join link was found. Otherwise **Directions** when the meeting is in person: its location names a physical place. `LocationFormatter.physicalPlace(in:)` splits the location on ";" and new lines and drops the virtual parts: links with or without a scheme ("meet.google.com/…"), phone numbers and dial-ins, bare service names ("Teams", "Zoom", "Online", …). "Sala Retiro; Microsoft Teams Meeting" keeps "Sala Retiro"; "Teams Room 3" stays a place. Directions opens Apple Maps (`https://maps.apple.com/?daddr=…`).
- **Locations.** `LocationFormatter` shortens the physical part for rows and cards. It finds the street first (a component followed by a house number, or one that starts with a number), then shows "name · locality" or "street · locality": "C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España" → "C. de Ruiz de Alarcón, 23 · Retiro"; "Museo del Prado, C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España" → "Museo del Prado · Retiro"; "1 Infinite Loop" over "Cupertino, CA 95014" → "1 Infinite Loop · Cupertino".

**Header menus.** Both are AppKit `NSMenu`s that pop up below their 28 pt button, right edges aligned.

- **Bell:** while active, a menu: "Pause for 1 hour", "Pause until tomorrow", "Pause until I resume" (tooltip and VoiceOver: "Pause full-screen alerts", hint "Opens a menu"). The choice goes to `AlertCoordinator.pause(_:)`, which persists it (§5). While paused the button shows `bell.slash`, is drawn pressed (selected for VoiceOver), is labelled "Resume full-screen alerts", and resumes directly, as in the Paused artboard.
- **Gear** (`gearshape`, VoiceOver "Settings", hint "Opens a menu"): "Settings ⌘,", "Quit Join! ⌘Q". The design's ⋯ menu and its Open Calendar item were dropped at the user's request. Updates didn't add a "Check for Updates…" item either: the user kept the menu to these two, and updates live in the update bar and Settings › General › Updates.

**No permission.** Without calendar access the panel shows an explanation, **Open System Settings** (`x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`) and **Check Again**. The update bar still shows, above the prompt.

## 8. Settings window

Dependent settings (Repeat until it's closed, the Custom time rows, the tint's Strength) are drawn as children of the row above: indented 30 pt, with their hairline starting at the indent and an elbow line running from under the parent's label to their own (`SettingsRow(indented:)`). They only show while their parent is on, and are hidden, never dimmed, while it's off: Repeat only with a sound, a Custom time row only while its pop-up is on Custom…, Strength only while there's a tint. The user asked for this for every nested option (2026-10-07). Hiding Repeat or Strength keeps its stored value, so it comes back as it was. A color well likewise only shows while its pop-up is on Other…, and a legacy Text row only while a label color saved by an earlier build is stored. Rows that sit beside a setting rather than under it are another matter: with **Alert me** on **Never**, **Show on**, **Sound** and Repeat stay in view, dimmed and disabled (below). A row appearing or disappearing resizes the window like any other height change (Sizing, below).

`SettingsWindowController` owns a plain AppKit window whose content view controller is an `NSTabViewController` with `tabStyle = .toolbar`: one toolbar item per pane, **General** (`gearshape`), **Calendars** (`calendar`), **Full-Screen Alert** (`bell`, the symbol of the panel's Pause full-screen alerts) and **Appearance** (`paintpalette`), in that order (`SettingsPane`: `general`, `calendars`, `fullScreenAlert`, `appearance`). Each pane has one subject, since the user's regroup for 1.2.0 (2026-10-08): General the app and the menu bar, Calendars the calendars, Full-Screen Alert when and where the alert shows and how it's snoozed and closed, Appearance how it looks. Full-Screen Alert's label is in title style, like other macOS toolbar items. SwiftUI's `Settings` scene can't be opened dependably from a menu-bar-only app. The window uses `toolbarStyle = .preference`, takes the selected pane's title, and can be closed but not resized. Panes switch instantly, as the user asked for 1.2.0: `transitionOptions` is empty, so there's no crossfade. It opens from the gear menu, ⌘, in the panel, reopening the app (`applicationShouldHandleReopen`), or the `openSettings` script hook (§12), which can also pick the pane.

**Sizing.** Each pane is a SwiftUI view in an `NSHostingView` with `sizingOptions = []`, wrapped in `SettingsPaneScroll`, which reports the content's natural height through a preference. The window keeps a 720 pt content width and takes the selected pane's height, in one step when switching panes, never animated (1.2.0 dropped the animated resize with the crossfade). A height change from within a pane (a style adding the tint's Strength row, or picking a sound bringing back Repeat, say) resizes it without animation on the next run-loop turn: SwiftUI reports the new height from inside its layout pass, and resizing the window there left the window's content view out of step with its frame by the height change, so the pane slid under the toolbar or below a gap. It keeps its top edge in place and stays on screen. It only scrolls when the screen is too short for the pane.

**Focus.** Opening the window, switching panes and closing the window all clear the first responder. That stops AppKit from focusing the first text field on open, and commits a half-typed value the same way as when the field loses focus.

**Components.** `SettingsComponents.swift` holds the shared building blocks, so the four panes look alike: `SettingsPalette` (window, box, separator, chip, field, connector and warning colors as light/dark pairs), `SettingsMetrics` (pane width, padding, indent), `SettingsSection` (a heading over a box), `SettingsBox` (the rounded group), `SettingsRow` (label left, control right, a hairline above, secondary or disabled tone, and an optional indent for dependent rows, which insets the hairline and draws an elbow connector in the gutter), `SettingsSwitchRow`, `SettingsWarning` (a line that reads as an alert: an orange `exclamationmark.triangle.fill`, then the message in `SettingsPalette.warning`, an orange that keeps 4.5:1 on the window and the boxes, `#A14C00` in light mode and the system orange in dark mode; the contrast warnings and Appearance's Never note use it), `SettingsFlowLayout` (a wrapping layout for tokens, where a subview tagged `SettingsFlowFill` takes the rest of its line), `SettingsMinutesChoice` (a pop-up of preset minutes plus Custom…, which adds the indented Custom time row with a field that saves on Return or focus loss and a stepper; **Alert me**, both snooze buttons and the menu bar's **Starting soon** use it, and only **Alert me** passes it a **Never** item; what the pop-up shows and what picking an item or saving a custom value changes is `MinutesChoice` in JoinCore, which the view calls, while the view keeps whether Custom… was picked, the draft, focus and which writes were its own) and `SettingsPaneScroll`. `SettingsColorChoice.swift` holds the color rows' controls on General and Appearance. `SettingsColorChoice` is a pop-up of named swatches, each with a dot, a separator and **Other…**; while Other… is picked a color well sits before the pop-up, so the pop-up keeps its place at the row's trailing edge, and picking Other… opens the color panel on that well at once. Which item shows, and what picking one changes, is `ColorChoice` in JoinCore (with `AlertColorRow` and `StartingSoonPill.colorChoice` for the lists); as with Custom…, the view keeps whether Other… was picked, so Other… stays chosen even while its color matches a swatch, as it often does at first, since it starts from the color shown, until another item is picked or the color changes from elsewhere (a Style card, Restore Defaults). The well, `SettingsColorWell`, is an AppKit `NSColorWell` hosted in SwiftUI, because SwiftUI's `ColorPicker` can't open the color panel from code; the panel is shared, so opening it from one well takes it from any other, and closing the Settings window closes it. The swatch dots (`SettingsSwatchDot`) are never template images, so the menu and the pop-up draw them in their own colors rather than tinting them. `SettingsLegacyTextChoice` is a legacy Text row's control: a well, then Automatic / Custom. The pop-up choices and their labels come from `SettingsOptions` in JoinCore, and the Updates section's words from `UpdateCopy`. All controls bind to `Preferences`.

- **General:**
  - Top box: **Open at login** (`SMAppService.mainApp.register()` / `.unregister()`; if macOS wants approval, a hint points to System Settings › General › Login Items; switch and hint are re-read whenever the app becomes active or Settings becomes key, so the hint clears after approval; in a fixture run the row is disabled, "Not available in fixture mode.", and never touches `SMAppService`).
  - **Menu bar**, the menu bar item and its starting-soon pill. Until the regroup (2026-10-08) **Menu bar** was a pop-up in the top box and the pill had a section on Appearance.
    - **Shows**: Icon only, Time until next event (the default), Title and time until next event (`MenuBarDisplay`, §7), one pop-up in place of the design's two switches.
    - **Starting soon**: a preview of the menu bar, then a pop-up of how long before a meeting the pill replaces the countdown (1, 3, 5 or 10 minutes before, or Custom… with a 1–60 minute Custom time row, like **Alert me**; 5 by default). The panel's starting-soon card follows the same setting. Help tag: "The menu bar shows the event like this from then on. The panel highlights it at the same time." The preview is the pill as the menu bar draws it, in the chosen color, with the text the menu bar would show for a demo event, composed by its own rules from **Shows** above (`MenuBarPresenter.startingSoonPreviewText`): "Next in 4 min", "Hello, I’m a demo event · in 4 min" (truncated as in the menu bar), or the icon alone; 4 minutes, or the pill's own time when that's shorter. VoiceOver calls it "Preview of the menu bar before an event", and the custom field "Minutes before the event". It was **Appears** on Appearance, under a "Starting in 5 min or less" preview row that's gone.
    - **Color**, a sibling of Starting soon rather than its child, since it doesn't depend on it: Accent color (the default), Red, Orange, Green, Blue, Graphite, then Other… with a well before the pop-up (`StartingSoonPill.colorChoice`; the user put Blue where the canvas had Purple). The swatches are the system colors' light-mode values, fixed sRGB. Other… starts from the color shown, so nothing changes until a new color is picked. VoiceOver: "Menu bar fill", and "Menu bar fill color" for the well. The text has no setting: it's Automatic, white unless the fill shown, the accent or a chosen color, gives white less than 3:1; then it's near-black. On macOS 27 that keeps white on the blue, purple, pink and red accents, and picks near-black on orange, yellow and green, where white is hard to read. The label is worked out when the pill is drawn, against the accent in that appearance.
    - **Text**, a legacy row (Automatic or Custom with a well; VoiceOver "Menu bar text"), only while a text color saved by an earlier build is stored. Automatic clears it, and the row goes.
    - A contrast warning under the rows, announced to VoiceOver, when the label falls below 3:1, in the alert's template (§6): "The menu bar item may be hard to read (2.1:1). Aim for 3:1, or set Text to Automatic." Automatic text always reaches 3:1, so only a legacy text color can cause it. That's lower than the alert's 4.5:1 by choice: white on the default blue accent is about 4:1, and the stock pill shouldn't be flagged.
  - **Events** (§4, §9a), in `EventsSection`: one section since 1.2.0, in place of 1.1's Events and Out of office sections. **Events with no participants**, a pop-up of **Show and alert** (the default), **Show in the list only** and **Exclude**, with no note under it: the user had the explanation 1.1 showed there removed (2026-10-07). **Out-of-office events**, the same pop-up, **Show in the list only** by default. Then **Out-of-office keywords** with a **Restore Defaults** link, which brings back the built-in list, and the keywords as removable tokens: Return or a comma adds a keyword, Delete in the empty field removes the last one, leaving the field adds what was typed, and duplicates are ignored regardless of case. A footnote closes the section: "An event counts as out of office when its title contains any of these words. Press Return to add one. Only Show and alert lets an event alert, take the menu bar or sit at the top of the panel. When an event is both kinds, the choice that shows less wins." The titles and the footnote come from `SettingsOptions`, the choices' names from `EventVisibility.title`. The section sits between Menu bar and Updates. Its layout is option B of the settings design canvas, which the user picked, with the word Exclude. The settings design put the out-of-office options on Calendars; they live on General by the user's choice.
  - **Updates** (§14), the last section: **Check for updates automatically** (`checksForUpdates`, on by default), then a row with the status line and the buttons. The line reads "Join! 1.0.0 · Checked 5 minutes ago" (counted like the Calendars pane's "Updated" label), "Join! 1.0.0 · Checking…", "Join! 1.0.0 · Couldn't check for updates", "Join! 1.0.0" before the first check, "Join! 1.1.0 is available", or "Join! 2.0.0 needs macOS 15.0 or later" for a release this Mac can't run (§14). While an update is on offer the line names it, whatever a later check is doing, so **Install** never sits beside a line without a version. **Check Now** checks even with the switch off; **Install** appears when an update is available, and turns into the update bar's **Download Page** or **Show in Finder** after a failed or revealed install. Both are disabled while a check or an install is running. Under the row, a failed install's reason shows in red (`UpdateCopy.failureReason`: "The download doesn't match the release's checksum.", "This version doesn't run on this Mac's processor.", …). In a fixture run everything works against the fixture feed (§12), but Install shows "Not available in fixture mode." unless `JOIN_FIXTURE_UPDATE=live`.
- **Calendars:** a line saying alerts come from the checked calendars, with "N of M selected", and an orange warning when none are selected ("No calendars selected: you won't get any full-screen alerts."). One group per account (`calendar.source.title`) with its own "N of M" and a **Select All** / **Deselect All** link when it has more than one calendar. Each calendar is a checkbox filled with the calendar's color; VoiceOver sees a standard checkbox. The first change turns the implicit "all calendars" (`nil`) into an explicit set. The choice for events with no participants, which is decided per event rather than per calendar, isn't here: it's on General (**Events**, above), since 1.1.1. Footer: where to add a missing account and where the sync interval is set, an "Updated just now" / "Updated 5 minutes ago" label from `MeetingStore.lastRefreshed`, **Open Internet Accounts…** and **Refresh Calendars**, which re-reads EventKit. Without calendar access the pane shows a permission prompt instead.
- **Full-Screen Alert**, new in the regroup (2026-10-08): its first box and its rules moved unchanged from General's **Full-screen alert** section, and Snooze & auto-close from Appearance, where it sat for a day and no release had it.
  - A box with no heading, since the pane names the subject. **Alert me**: When the event starts, 1 minute before, 3 minutes before (the default), 5 minutes before, **Never**, then a separator and Custom…. Custom shows an indented row with a minutes field and a stepper (0–120). The field saves on Return or when it loses focus, never mid-typing, so "3" → "35" → "5" can't briefly mean 35 minutes and fire alerts early. A stored lead time that isn't a preset opens as Custom, including the 2 and 10 minutes that were presets before 1.2.0. **Never** sets `fullScreenAlertsEnabled` to false and leaves `leadTime` alone; while alerts are off the pop-up shows Never, whatever the lead time. A preset turns alerts back on at once with its time, and so does Custom…, with the kept time in its field to change: what the pop-up shows is always what's in effect. `MinutesChoice` (JoinCore) holds this rule; its items are cases of their own, so Never can't be taken for a preset (not even When the event starts, 0) or for Custom…. With Never the box's other rows stay in view but are disabled, as the user asked (2026-10-07; at first they stayed enabled): **Show on**, **Sound** and, while a sound is chosen, **Repeat until it's closed** take the disabled tone (`SettingsRow` `.disabled`, a tertiary label), and their controls, the Show on pop-up, the Sound pop-up and its play button and the Repeat switch, are disabled. Their stored values don't change, and picking a time enables them again. They're siblings of Alert me rather than children, so the hide-while-off rule above doesn't apply to them; Repeat still hides while Sound is None. **Show on**: All screens (the default), Main screen only, Secondary screen only, Screen with the pointer (`AlertScreens`, §6). The main screen is the one with the menu bar; Secondary screen only is every other screen, or the main one when it's the only screen. Secondary screen only is new in 1.2.0, between Main screen only and Screen with the pointer. **Sound**: a play button (tooltip and VoiceOver "Play the sound") and a pop-up with None and the `/System/Library/Sounds` names. The indented **Repeat until it's closed** only shows while a sound is chosen: with None it's hidden, and keeps its stored value for when a sound is picked again. Before 1.1.1 it showed dimmed and disabled.
  - **Snooze & auto-close:** **First snooze button** and **Second snooze button** (1, 3, 5 or 10 minutes, or Custom… with a 1–120 minute field, like **Alert me**; a value saved by an earlier build, such as 30 minutes, shows as Custom) and **Close automatically** (Never, or after 5, 10, 15, 30 or 60 minutes; it read **Close full-screen alerts automatically** until the pane took the noun). These rows stay enabled while Alert me is Never: the user scoped the dimming to Show on, Sound and Repeat. Both snooze buttons on the same duration give the alert one button for it (§6). The "The full-screen alert offers" chips that mirrored the alert's snooze row are gone: Appearance's preview shows the row itself, following these durations as they change.
  - **Show Demo**, at the bottom right, beside the settings it shows off (§5). Its help tag reads "Shows a real full-screen alert with a sample event. Press Esc to close it.", or, while a real alert is on screen and the button is disabled, "Close the current full-screen alert first." Appearance has the same button.
- **Appearance**, the full-screen alert's look and nothing else since the regroup:
  - A live preview at the top: the real `AlertContentView` at 56 % scale, cropped to about 236 pt so little empty backdrop shows around the alert, with a sample meeting frozen at "Starts in 2:59", over a sample screen picked with **Preview over**: Wallpaper, Light window or Dark window (until the regroup **Preview on**: Wallpaper, Light app, Dark app). A window can't blur what is behind it inside itself, so the sample screen is drawn already blurred, and the palette's `material` is laid over it as a plain layer, then the tint and scrim as on the real alert. VoiceOver calls it "Live preview of the full-screen alert". **Show Demo** sits at the end of the Preview over bar, with the same help tags as on Full-Screen Alert.
  - While **Alert me** is **Never**, a note right under that bar, a `SettingsWarning`: an orange `exclamationmark.triangle.fill`, then "Alert me is set to Never in Full-Screen Alert. Show Demo still works." in an orange that keeps at least 4.5:1 on the pane, darker than the system orange in light mode (`#A14C00`) and the system orange itself in dark mode. The user asked for orange so it's easy to see and reads as an alert (2026-10-08). Nothing on the pane is dimmed: Never stops real alerts only, and its dimming stays on the Full-Screen Alert pane.
  - **Style:** five cards, drawn as miniatures: the presets Dark (help tag "The default style."), Light, High contrast and Midnight, then **Custom**. The card of `appearance.style` gets an accent ring, and every label stays primary, so no card looks disabled. Custom is always there. Until the user has a look of their own it's a placeholder, with the help tag "Change any color below to make your own style.", and does nothing when clicked; then it's a miniature of `Preferences.customAppearance` (`AlertAppearance.swatch`), and clicking it puts that look back (`applyCustomAppearance()`). Any look that matches no preset is saved there as it's set; clicking a preset, or Restore Defaults, leaves it alone.
  - **Colors:** one box, every row always in view, which was headed **Full-screen alert** until the regroup gave that noun its own pane. **Backdrop**, a segmented control: Dark blur and Light blur, plus No blur only while a look saved by an earlier build has it (`backdropChoices`). **Tint**: None (the default), Black, Navy, Plum, Forest, Other…, with the indented **Strength** slider (VoiceOver "Tint strength"; 35 % by default) while there's a tint. **Event text**: Automatic, Other…. **Join button**: Orange (the default), Yellow, Blue, Green, Purple, Red, Graphite, Other…. **Snooze & Dismiss buttons**: Automatic (the default), White and Black at 22 %, Other…, whose well also picks an opacity (VoiceOver "Snooze and Dismiss buttons"). Every preset's colors are among the swatches, so a preset never shows Other…. The rows, their swatches and their VoiceOver names are `AlertColorRow` in JoinCore; picking an item is `AlertAppearance.pick(_:for:)`, the well `setColor(_:for:)`. A swatch sets its color exactly, opacity included; Orange is the automatic Join color, so picking it stores none. Other… starts from the color shown, so nothing changes until a color is picked in the well, except from a Tint of None, where it adds a `#7A5AF8` tint at the current Strength at once, and the Strength row appears; the well's color is kept as picked, even when it equals the automatic one. Editing any row selects the Custom card, unless the result is a preset's look. Under the Join button and the Snooze & Dismiss buttons, a legacy **Text** row (Automatic, or Custom with a well) shows only while a label color saved by an earlier build is stored: Settings no longer sets label colors, nor Join's fill opacity. Its Automatic clears the color, and the row goes. Each contrast warning shows directly under the row it belongs to (`AlertContrastWarning.row`, §6), below that row's Text row if it has one.
  - **Restore Defaults**, a push button at the bottom right of the pane, puts back the look only: the Dark style and its default colors (`Preferences.resetAppearance()`). The Custom card's look, the snooze buttons, auto-close and the menu bar pill stay as they are. It's disabled while `appearance.isDefault`: the look is Dark's, with no Text row and no row on Other… but Join's, which at its default Orange still counts as the default (§6). The user asked for the button (2026-10-08). Until the regroup it also reset the snooze buttons, auto-close and the pill, then on this pane.

**Persistence.** `Preferences` is an `@Observable` class whose stored properties read/write `UserDefaults` (theme encoded as JSON `Data`). No `@AppStorage` scattered across views; one owner. Values stored by older builds are migrated on load:

- Lead times with seconds are rounded to whole minutes. Every write is rounded too.
- The old `showOnAllScreens` Bool becomes `alertScreens`: true → all screens, false → main screen. Writing the new key removes the old one.
- `alertScreens` gains `secondary` in 1.2.0; `all`, `main` and `pointer` keep their stored values. Builds before 1.2.0 don't know `secondary` and show the alert on all screens.
- `menuBarShowsEventTitles` is new and starts off. Builds before the redesign always showed the title.
- `checksForUpdates` is new in 1.1.0 and starts on, so a copy updated by hand from 1.0.0 checks from its first launch.
- `eventsWithoutParticipants` is new in 1.2.0. Until it's set, it comes from 1.1's switch, `showsEventsWithoutParticipants`: on or absent → Show and alert, off → Exclude.
- `outOfOfficeEvents` is new in 1.2.0. Until it's set, it comes from the two out-of-office switches of 1.0 and 1.1. `alertForOutOfOffice` on → Show and alert, whatever `showOutOfOfficeInList` says, so those alerts keep working. With it off, `showOutOfOfficeInList` on or absent → Show in the list only, off → Exclude. When `alertForOutOfOffice` is absent, the inverse of the older `skipOutOfOffice` stands in for it, and with neither it counts as off.
- Setting either choice removes the old keys it was read from, as `alertScreens` does. A stored value that isn't one of the three choices is ignored, so the old keys or the default apply.
- `fullScreenAlertsEnabled` is new in 1.2.0 and starts on. A stored lead time of 2 or 10 minutes is kept and shows as Custom.
- The appearance JSON migrates as described in §6.
- `customAppearance` is new in 1.2.0. On the first load without it, a stored appearance that matches no preset becomes the Custom card's look and is saved as such, so a look of the user's own opens on Custom. A stored one that matches a preset is ignored.

## 9a. Out-of-office events

EventKit doesn't expose Google's "out of office" event type, but Google titles those events predictably in the account's language ("Out of office", "Fuera de la oficina", …). `OutOfOfficeDetector` matches the title against a keyword list (short tokens like "OOO" and "PTO" must stand alone), edited under **Out-of-office keywords** in Settings › General › Events. What happens to matching events is the **Out-of-office events** choice in the same section (§4). It's **Show in the list only** by default: they never alert and don't drive the menu bar item or the panel's hero card, and they appear in the panel's lists as striped, muted rows with no button. **Show and alert** lets them alert and drive the menu bar like any other event, still striped in the lists; **Exclude** leaves them out everywhere. Whatever the choice, they never count as overlaps.

An out-of-office block nobody else is on is also an event with no participants, so it gets whichever of the two choices shows less: with **Events with no participants** on Exclude, it's left out whatever the out-of-office choice says. One with participants follows the out-of-office choice alone.

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

Adding a provider is one table row plus a test case. Opening uses `NSWorkspace.shared.open(url)` (system default browser or handler). A meeting with no link but a physical location gets a Directions button in the panel instead (§7).

## 10. Edge cases handled

| Case | Behaviour |
|---|---|
| Mac asleep through the fire time | On wake: refetch, `nextPlan` sees `fireAt < now < end` → fires immediately. |
| App launched 1 min before a meeting | Same path: fires on first plan. |
| Meeting created less than `leadTime` before start | `EKEventStoreChanged` → re-plan → fires now. |
| Meeting cancelled while alert showing | Store no longer contains it → coordinator closes the alert. |
| Meeting moved | New `id`, old state discarded, new occurrence scheduled. |
| An event only you are on (focus time, a reminder, a hold) | Shows and alerts like any other by default. On **Show in the list only** it stays in the panel's lists only; on **Exclude** it's left out of the panel, the menu bar and alerts. Choosing Show and alert again brings it back at once. |
| An event's Events choice changes away from Show and alert while its alert is on screen | It leaves `alertableMeetings`, so the alert closes, as for a cancelled meeting. |
| An out-of-office block nobody else is on | It's both kinds, so the choice that shows less applies (§9a). |
| **Alert me** set to **Never** while an alert is on screen | The alert stays until it's closed; pending and snoozed alerts don't fire. The menu bar and the panel carry on. |
| A time picked again after **Never** | Re-plan with that time; a meeting that started less than 5 minutes ago alerts right away, as when a pause ends. |
| Two meetings at the same time | One alert listing both. |
| Next meeting starts while you're in one | Within the starting-soon window (5 minutes by default) it takes over the menu bar item (pill) and the panel's hero card; the ongoing one moves to "Now". |
| Two meetings overlap | The later one is flagged in the panel ("Overlaps …"); both alert normally. |
| Meeting runs past midnight | Time range reads "11:30 PM – 12:30 AM"; longer than a day, "Mon 9:00 AM – Wed 5:00 PM". `DateIntervalFormatter` alone prints full dates as soon as a range crosses midnight. |
| Lead time changed in Settings | Re-plan; a meeting already `.dismissed` stays dismissed. |
| Sound set to None while **Repeat until it's closed** is on | The Repeat row hides and its stored value is kept; with no sound there's nothing to repeat. Picking a sound again shows the switch, still on. |
| Paused until tomorrow, then the app relaunches | The pause is read back from UserDefaults; an expired one is dropped. |
| A timed pause runs out | The next heartbeat (≤ 30 s) clears it; a meeting about to start alerts right away. |
| User in a full-screen app on another Space | `.canJoinAllSpaces` + `.fullScreenAuxiliary` + `.screenSaver` level shows over it. |
| Display plugged/unplugged during alert | Windows rebuilt from current `NSScreen.screens` (for "Screen with the pointer", the screen the pointer is on at that moment; for "Secondary screen only", the main screen once no other is left). |
| More meetings than fit in the panel | The panel stops at 640 pt or the bottom of the screen and scrolls, with a fade at the bottom. |
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
│   │   Meeting (and MeetingFilter), EventVisibility, AlertState, AlertScheduler,
│   │   AlertScreens, PauseState, MeetingLinkDetector, OutOfOfficeDetector,
│   │   MeetingTimeFormatter, MenuBarPresenter, PanelPresenter, LocationFormatter,
│   │   AlertCountdown, AlertAppearance (presets, styles, palette, contrast,
│   │   migration), AlertColorRow (Appearance's color rows), ColorChoice (the
│   │   color pop-ups' swatches and Other…), StartingSoonPill (window, colors,
│   │   contrast), RGBA, SettingsOptions,
│   │   MinutesChoice (the minutes pop-ups' presets, Never and Custom…),
│   │   Preferences, AppVersion, UpdateCheck (GitHub release, AvailableUpdate,
│   │   UpdateStatus, UpdateFailure, UnsupportedUpdate), UpdateCopy
│   └── Join/                The app
│       ├── App/             JoinApp (scenes), AppDelegate (script hooks), AppModel (wiring, clock)
│       ├── Calendar/        CalendarService (protocol), EventKitCalendarService,
│       │                    FixtureCalendarService, MeetingStore
│       ├── Alerts/          AlertCoordinator, AlertWindowController, AlertView
│       ├── MenuBar/         StatusItemController, StatusItemImages, MenuBarPanelWindow,
│       │                    MenuBarPanelView, PanelHeroView, PanelRowView, PanelStyle
│       ├── Settings/        SettingsWindowController, SettingsComponents, GeneralTab,
│       │                    SettingsColorChoice, EventsSection, CalendarsTab,
│       │                    FullScreenAlertTab, AppearanceTab, AppearancePreview
│       ├── Updates/         ReleaseFeed (GitHub, fixture), UpdateChecker, UpdateInstaller
│       └── Support/         Observation helper, Color↔RGBA, SystemSounds, LaunchAtLogin,
│                            WindowSnapshots
├── Tests/JoinCoreTests/     XCTest suites for everything in JoinCore
├── Resources/
│   ├── Info.plist           LSUIElement, usage description, bundle metadata
│   └── AppIcon.icns         The app icon, drawn by scripts/make-icon.swift (see §13)
├── scripts/
│   ├── build-app.sh         Assembles build/Join.app and signs it (see §13)
│   ├── make-icon.swift      Draws the app icon into AppIcon.icns and docs/AppIcon.png
│   └── release.sh           Sets the version, tags vX.Y.Z on main and pushes (see §13)
├── Makefile                 make app | icon | release | run | test | clean
├── .github/workflows/
│   ├── ci.yml               build + test + universal package on macos-15, every push to main and PR
│   └── release.yml          on a vX.Y.Z tag: test, universal build, GitHub Release with Join.zip
└── docs/                    This document, the product brief, RELEASING.md, and AppIcon.png for the README
```

Bundle id `com.poliuk.join`, `LSUIElement = YES`.

## 12. Testing strategy

- **Unit tests (XCTest) on `JoinCore`:**
  - `AlertScheduler` (every row of the edge-case table above with a fixed `now`), `MeetingLinkDetector` (one fixture per provider plus negatives), `MeetingFilter` (which events are kept; every pair of Events choices against an ordinary event, one with no participants, one out of office and one of both kinds, for the visible and the alertable lists; alertable always within visible), `EventVisibility` (order, titles, raw values), `OutOfOfficeDetector`, `AlertScreens` (order, titles, raw values, and the screens chosen with 0 to 3 screens and the pointer on each, including the fallbacks to the main screen).
  - `MeetingTimeFormatter`, including ranges across midnight and longer than a day.
  - `MenuBarPresenter` (every status item state, precedence, titles on and off, durations, the paused message and label, the header date, the Starting soon preview's text), `PanelPresenter` (each hero, the rows drawn in the design, day headings, overlaps, out-of-office rows, ended meetings left out, the Today | 7 Days filter, the list for each out-of-office choice), `PanelPalette` (every ink on the frost over the measured glass, the starting-soon card and the accent button for every system accent), `LocationFormatter` (short locations, physical places, directions URL), `AlertCountdown` (phases, texts, snooze labels, each snooze duration once), `PauseState`.
  - `AlertAppearance`: `RGBA` hex, compositing, contrast and 8-bit keys; JSON round-trip; legacy JSON migration and version 2 → 3 (presets remapped first, High contrast's old black label included; translucent automatic fills to Other…; legacy label rows kept); presets and preset matching on the resolved palette; the Style cards, the Custom card's miniature and `isDefault`; automatic colors; the Colors rows' swatch lists and copy, which item each shows, picking a swatch or Other…, well colors kept as picked, and editing any row selecting Custom; every preset showing a swatch in every row, and every button swatch reading on every preset; legacy Text rows; contrast warnings, their wording and the row each shows under; switching between Automatic and Custom. `StartingSoonPill`: the window, automatic text reading on every gray and swatch, the Color list (Blue, no Purple), which item it shows, the legacy Text row and the warning.
  - `Preferences` round-trip through an isolated `UserDefaults` suite, every **Show on** choice included, plus each migration in §8, including every combination of the old out-of-office switches, Appearance's Restore Defaults, which restores the look only (the Custom card's look, the snooze buttons, auto-close, the pill, the lead time, Never and the sound stay), and the Custom card's look: kept from the last look of the user's own, seeded from a stored one on the first load, and absent while the stored look, or a stored card look, matches a preset. `SettingsOptions`: pop-up choices, including Never and the lead times that now show as Custom, the "Updated" label, calendar selection, keyword tokens, the Events section's titles and footnote, and the panes' copy (the Menu bar section, Starting soon and Color, Close automatically, Show Demo's help tags, Colors, the Never note). `MinutesChoice`: what **Alert me** shows for each lead time with alerts on and off (a stored 2 or 10 is Custom… only while they're on), Never kept apart from When the event starts and Custom…, what picking a preset, Never or Custom… changes, a saved custom value turning Never off only while Custom… is picked, and the snooze and **Starting soon** pop-ups, which have no Never.
  - Updates: `AppVersion` (parsing, including what it rejects, ordering, tags), `UpdateCheck` (decoding a sample shaped like GitHub's real response, which releases count as an update, the URLs built from the tag, the digest, and when a check is due), `UpdateCopy` (every string in Settings › General › Updates and on the update bar, including each install failure's reason, the unsupported line and the offer naming the line whatever the status). `Preferences` covers the update keys' defaults, persistence and removal.
  - `MenuBarFixtures` holds the week drawn in the menu bar design (Monday 5 – Thursday 8 October 2026) in UTC, with `en_US` and `en_GB` locales, so the presenter tests check the design's exact strings and don't depend on the machine's time zone.
- `swift test` needs XCTest, which ships with Xcode, not with the Command Line Tools. CI runs the suite on every push to main and every pull request. Locally without Xcode the suite can't run; `swift build` still works.
- **Fixture calendars.** The `JOIN_FIXTURE` environment variable swaps EventKit for `FixtureCalendarService`, so the menu bar and Settings can be checked in a known state:

  ```sh
  make app
  open --env JOIN_FIXTURE=busy build/Join.app
  ```

  | Scenario | Today |
  |---|---|
  | `nothing` | no more meetings today |
  | `later` | an in-person appointment in 2 h 15 min, then a video call |
  | `busy` | one call started 56 min ago; another starts in 4 min |
  | `meeting` | in two overlapping calls |
  | `maybe` | a Maybe block started 18 min ago; a call you accepted starts in 47 min, and drives the menu bar and the card |
  | `denied` | calendar access denied, so the permission prompts show |

  `JOIN_SETTINGS_MAX_HEIGHT=<points>` (fixture runs only) caps the Settings window's content height, to check the scrolling layout of a short screen on a tall one.

  `JOIN_FIXTURE_UPDATE` (fixture runs only) picks what the update check finds, through `FixtureReleaseFeed`: `current` (the default) the running version, `available` a release one minor version above it with a Join.zip, `failed` an error. None of them touches the network, and with them Install shows "Not available in fixture mode." `live` uses `GitHubReleaseFeed` and lets Install download, verify and install a real release, replacing the bundle the fixture runs from; it's only for testing updates end to end. Except with `live`, a fixture run keeps the update check's results (when it last checked, the offered and the unsupported versions) in memory only, never in the fixture defaults, so every fixture launch checks once, straight away, and each value shows its result whatever an earlier run found. When Join! can't replace itself, a fixture run reveals the new copy in `$TMPDIR/JoinUpdate/`, never in ~/Downloads, and a fixture relaunched after an install keeps `JOIN_FIXTURE` and `JOIN_FIXTURE_UPDATE`.

  ```sh
  open --env JOIN_FIXTURE=busy --env JOIN_FIXTURE_UPDATE=available build/Join.app
  ```

  `JOIN_FIXTURE_REGULAR=1` (fixture runs only) gives Join! a Dock icon and a menu bar of its own, so UI automation tools that only see regular apps can click through Settings. Some bugs only show up with real clicks, not with the script hooks below.

  Every scenario has the same following days: tomorrow an out-of-office block, an in-person appointment and two overlapping calls, then more meetings on the two days after, including a Focus time block the day after tomorrow (14:00–15:00, on the personal calendar, with no link). The out-of-office block and Focus time have no participants, so setting **Events with no participants** to **Exclude** (Settings › General › Events) hides both, whatever the out-of-office choice; every other fixture meeting has participants. Five calendars in two accounts fill the Calendars pane. Times are relative to launch, rounded to the minute. Only these six names turn fixture mode on; any other value is logged and ignored, so a typo launches the real app. A fixture run uses its own defaults domain (`com.poliuk.join.fixture`), so it can't change real settings, never starts the alert scheduler, so it can't put an alert on screen by itself, leaves the login item alone, and doesn't go online for updates unless `JOIN_FIXTURE_UPDATE=live`. It shows a "Fixture" marker in the panel header and the Settings title, and it quits after two hours so a forgotten one can't silence real alerts for long. Show Demo still works. Quit a running Join! first: `open` hands the request to the running copy instead of starting a new one, and the variable is lost.
- **Script hooks.** To drive a fixture run from scripts without clicking, `AppDelegate` listens for distributed notifications named `com.poliuk.join.fixture.<hook>`. Only fixture runs register them: any process can post a distributed notification, so a normal run must not let one pause, dismiss or capture the real app. The notification's object, when present, is the argument.

  | Hook | Argument | Does |
  |---|---|---|
  | `openSettings` | `general`, `calendars`, `fullScreenAlert` or `appearance` (optional) | opens Settings, on that pane if given |
  | `snapshot` | a folder name (default `latest`) | writes a PNG of every visible window of the app (`NN-<window class>-<title>.png`) into `$TMPDIR/JoinSnapshots/<name>`, without screen-recording permission; the name is reduced to one safe path component |
  | `showDemoAlert` | – | shows the demo full-screen alert, like **Show Demo** |
  | `dismissAlert` | – | dismisses the alert on screen, like clicking Dismiss |
  | `togglePanel` | – | opens or closes the menu bar panel |
  | `pause` | `oneHour`, `untilTomorrow` or `untilResumed` | pauses full-screen alerts; ignored without a valid option |
  | `resume` | – | resumes full-screen alerts |
  | `appearance` | `light`, `dark`, anything else follows the system | forces the app's light or dark appearance |
  | `preset` | `dark`, `light`, `highContrast` or `midnight` | applies an alert style preset, as clicking its card in Appearance does |
  | `panelFilter` | `today` or `week` | sets the panel's Today \| 7 Days choice |
  | `panelFrost` | an opacity from `0` to `1`, anything else for the default | tries another frost opacity on the open panel; Reduce Transparency still makes it opaque |
  | `checkForUpdates` | – | checks for updates now, like **Check Now** |
  | `installUpdate` | – | installs the available update, like **Install** |

  The app is usually inactive, so post with immediate delivery. From a shell:

  ```sh
  hook() {
    osascript -l JavaScript -e 'function run(argv) {
      ObjC.import("Foundation")
      $.NSDistributedNotificationCenter.defaultCenter
        .postNotificationNameObjectUserInfoDeliverImmediately("com.poliuk.join.fixture." + argv[0], argv[1] || null, null, true)
    }' "$@"
  }
  hook togglePanel
  hook appearance dark
  hook snapshot busy-dark   # → $(getconf DARWIN_USER_TEMP_DIR)JoinSnapshots/busy-dark
  ```

- **Manual smoke checklist** for the UI: each fixture scenario in light and dark; a long panel (scrolling and fade); pause and resume, including across a relaunch; each Events choice for both kinds of event; **Alert me** set to Never and back (Show on, Sound and Repeat dimmed and disabled, then enabled; the snooze rows enabled throughout; the orange note on Appearance in light and dark); switching Settings panes (instant, no crossfade), and every pane at `JOIN_SETTINGS_MAX_HEIGHT=720` as well as uncapped; each Colors row's swatches, Other… and its well, the Custom card kept across a preset and Restore Defaults; the menu bar preview for each **Shows** choice; the demo full-screen alert with each preset, on all screens, the main screen (with Settings open on a secondary display), the secondary screens (and with only one display connected) and the pointer's screen; snooze and "At event start"; full-screen app on another Space; sleep/wake with a meeting 2 minutes out; the update bar and Settings › General › Updates with `JOIN_FIXTURE_UPDATE=available` and `failed` (a failed check shows only in Settings).
- **No UI tests**; the AppKit window behaviour isn't meaningfully testable headless.

## 13. Build, CI, distribution

- **Build:** `make app` runs `scripts/build-app.sh`: `swift build -c release` once per architecture in `ARCHS` (this Mac's by default; releases pass `arm64 x86_64`), joins the binaries with `lipo` (with `--disable-build-manifest-caching`, because SwiftPM 5.10 shares one cached manifest between architectures and fails the next build that reuses it), copies it, `Info.plist` and `AppIcon.icns` into `build/Join.app`, and ad-hoc signs it with an explicit designated requirement, `identifier "com.poliuk.join"`. A plain ad-hoc signature's requirement is the hash of that exact binary, so TCC treated every rebuild as a new app and asked for calendar access again. Pinning the requirement to the bundle identifier keeps the grant across rebuilds. The trade-off: any locally built binary that claims that identifier inherits the grant, which is acceptable for a locally built app and goes away with a real signing identity. `make run` builds and opens it.
- **App icon:** an amber tile with a white countdown ring, three quarters left from twelve o'clock, around a dark camera. `scripts/make-icon.swift` draws it with Core Graphics on the macOS icon grid (a 1024-point canvas, an 824-point tile with 186-point corners, room for the shadow), renders every size of the iconset from the vectors rather than scaling one bitmap down (only the Retina files for 16 and 32 points: `iconutil` would store 1x files at those sizes in a legacy format that macOS 26 and later shrink onto a grey plate), and runs `iconutil` to write `Resources/AppIcon.icns`, plus `docs/AppIcon.png` for the README. `Info.plist` names it with `CFBundleIconFile`. The `.icns` is committed, so building needs neither the script nor `iconutil`; run `make icon` after changing the drawing. On macOS 26 and later the system masks the tile to its own icon shape and adds its glass edge; the icon fills the shape, so it isn't shrunk onto a grey plate. There are no dark or tinted variants: those need an Icon Composer `.icon` compiled by `actool`, which comes with Xcode. The app has no Dock icon, so the icon shows in places like Finder, Spotlight, Login Items, System Settings › Privacy & Security › Calendars and the system's calendar access alert.
- **CI:** GitHub Actions on `macos-15` (its default Xcode; `swift-tools-version:5.10` keeps the Swift 5 language mode), on every push to main and every pull request: `swift build`, `swift test`, a universal `scripts/build-app.sh` like a release's, and the app, zipped with `ditto` because artifact uploads drop the executable bit, is kept as a workflow artifact. CI never publishes anything. `macos-14` was dropped because GitHub retires that image on 2 November 2026.
- **Releases:** pushing a tag `vMAJOR.MINOR.PATCH` runs `release.yml` on `macos-15`. It checks that the tag is `vMAJOR.MINOR.PATCH` with no leading zeros (`AppVersion`'s rule, so installed copies can offer it), matches `CFBundleShortVersionString` and is on main, runs `swift test`, builds a universal app (`ARCHS="arm64 x86_64"`), zips it with `ditto -c -k --keepParent` (which keeps the signature valid), and creates the GitHub Release with `gh release create --verify-tag --generate-notes`, attaching `Join.zip`. GitHub's generated notes only list merged pull requests, so the workflow puts the commit subjects since the previous tag above them (without the "Release x.y.z" commits). The asset keeps that name in every release, so `releases/latest/download/Join.zip` always gets the newest build. The in-app update check (§14) relies on the same things: the `vX.Y.Z` tag, an asset named `Join.zip`, and the SHA-256 digest GitHub records for each uploaded asset. `scripts/release.sh` (`make release VERSION=x.y.z`) makes the tag: it requires a clean, up-to-date main and a version of three numbers without leading zeros, newer than the last tag, writes the version into both `CFBundleShortVersionString` and `CFBundleVersion`, commits "Release x.y.z" if that changed anything, makes an annotated tag, and pushes main and the tag atomically after asking. The branch model and recovery steps are in [RELEASING.md](RELEASING.md).
- **Distribution:** ad-hoc signed, not notarized, by decision. Gatekeeper blocks the first launch of each version downloaded in a browser until the user clicks Open Anyway in System Settings › Privacy & Security (on macOS 14, right-click › Open also works). A locally built copy isn't quarantined and opens directly, and neither is a version the app installs itself (§14), so Open Anyway is only needed for a copy downloaded by hand. TCC keeps the calendar grant across versions because every build, local or CI, has the same designated requirement. Notarization (Developer ID + `notarytool` before the zip) can be added to `release.yml` later without touching the app.
- **Sandbox:** off. Sandboxing requires a real signing identity to be meaningful; nothing in the app needs it. The updater (§14) also relies on it being off: it replaces the app's own bundle and can write to ~/Downloads.
- **Updates:** from 1.1.0, Join! checks GitHub once a day and, when the user clicks Install, installs the new release itself, without Sparkle (§14). Copies of 1.0.0 have no updater and must be updated by hand once.

## 14. Updates

From 1.1.0, Join! looks for a newer release once a day and can install it itself. The user chose this on 2026-10-07: a daily check against GitHub, on by default with a switch in Settings › General › Updates, and an **Install** button that downloads the new version inside the app, so it isn't quarantined and needs no Open Anyway. 1.0.0 has no updater; copies of it are updated by hand once.

**Check.** `UpdateChecker` (`@MainActor @Observable`, owned by `AppModel`) asks a `ReleaseFeed` for the latest release. `GitHubReleaseFeed` sends one unauthenticated GET to `https://api.github.com/repos/Poliuk/join/releases/latest` with `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `User-Agent: Join/<version>` and `Accept-Language: en`, on an ephemeral `URLSession` (no cookies, no cache) with a 20 s timeout. A 200 is decoded with `UpdateCheck.decodeRelease`; any other status is a failure. No token is shipped or used. The language header is set because `URLSession` would otherwise send the user's own languages and region (`en-GB,en;q=0.9`, say); the app is English only. So apart from the version in the User-Agent the request carries nothing about the user, but GitHub sees the Mac's IP address. The download (Install, step 2) sends the same User-Agent and `Accept-Language`.

`UpdateCheck.update(current:release:)` (JoinCore) turns the release into an `AvailableUpdate`, or nil when the release:

- isn't newer than the running app's `CFBundleShortVersionString`,
- is a draft or a prerelease,
- has a tag that isn't exactly `vX.Y.Z` (`AppVersion`: three numbers, no leading zeros, no suffix),
- has no `Join.zip` asset, or one that is empty or larger than 100 MB.

The update's page and download URLs are built from the validated tag (`https://github.com/Poliuk/join/releases/download/vX.Y.Z/Join.zip`); no URL from the response is ever followed. The asset's `digest` (`sha256:<hex>`) gives the expected SHA-256, or none when it's missing or malformed. A build whose version doesn't parse (`currentVersion` nil) never checks.

**Schedule.** `AppModel` calls `UpdateChecker.start(now:)` from its own `start()`, and `tick(now:)` from its 30-second clock and on wake (`NSWorkspace.didWakeNotification`). `UpdateCheck.isDue` decides: the switch is on; there has been no successful check yet, or the last one (`Preferences.lastUpdateCheck`) is at least 24 hours old, or in the future because the clock moved back; and no check has failed in the last hour. A success stores its time and the version it offered (`Preferences.offeredUpdateVersion`, nil when it found none). A failure is kept in memory only, so a relaunch may try again sooner. **Check Now** checks whatever the switch says. One check runs at a time, and nothing installs while one runs: `installUpdate()` refuses, and Install is disabled in the panel and in Settings.

The offer itself isn't kept across launches, only its version. At launch (`start(now:)`), with the switch on and `offeredUpdateVersion` newer than the running version, `UpdateChecker` checks at once, due or not, and shows no offer until that check succeeds; if it fails (Join! opened at login before the network was up, say), it's retried an hour later like any failed check, not at the next daily one. Otherwise it ticks as usual. So an update found yesterday is offered again after a relaunch, but only if it's still the latest release. Together this makes about one request a day per Mac: one an hour while checks keep failing, plus one at a launch after a failure or while an update is on offer. Fixture runs keep `lastUpdateCheck`, `offeredUpdateVersion` and `unsupportedUpdate` in memory unless `JOIN_FIXTURE_UPDATE=live` (§12).

**Failures are quiet.** Being offline, a 403 or 429 (GitHub allows 60 unauthenticated requests an hour per IP address), a 5xx or JSON that doesn't decode all end in `UpdateStatus.failed`: Settings says "Couldn't check for updates", the panel shows nothing, and a failed automatic check never shows an alert.

**Install.** `UpdateInstaller` does the work and returns `.relaunching` or `.revealed(URL)`, or fails with an `UpdateFailure` (JoinCore: `download`, `tooLarge`, `checksum`, `unzip`, `notJoin`, `wrongArchitecture`, `unsupportedSystem(minimum)`, `signature`, `save`, `relaunch`). `UpdateChecker.install` follows it as an `UpdateInstallState` (`idle`, `downloading(fraction)`, `installing`, `revealed(URL)`, `failed(UpdateFailure)`) for the update bar (§7) and Settings (§8), and `UpdateCopy.failureReason` says why in words ("The download didn't finish.", "This version needs macOS 15.0 or later.", …). The steps:

1. Make a working folder: an item-replacement directory on the app's volume (`FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: Bundle.main.bundleURL, create: true)`), so the swap in step 6 stays on one volume, or a temporary directory if that fails. It's removed afterwards.
2. Download `Join.zip` from the URL built from the tag with a `URLSession` data task whose delegate writes the bytes straight into `Join.zip` in the working folder, reporting progress. Only a 200 (after redirects) is accepted. A download that announces more than 100 MB is refused before its first byte, and one that grows past 100 MB is cancelled as soon as it does (`tooLarge`). Nothing goes through `URLSession`'s own temporary files, so a failed or cancelled download leaves nothing behind once the working folder is removed. The session is invalidated afterwards.
3. Check its SHA-256 (CryptoKit) against the digest, when the release has one.
4. Unzip it with `/usr/bin/ditto -x -k`.
5. Verify the unzipped `Join.app`: its bundle identifier is the running app's (else `notJoin`), its `CFBundleShortVersionString` is the expected version (`notJoin`), its `LSMinimumSystemVersion` isn't above the running macOS (`unsupportedSystem`), its executable has a slice for this Mac's processor, arm64 on Apple silicon and x86_64 on Intel, as `Bundle.executableArchitectures` lists them (`wrongArchitecture`; checked after the macOS version, so a release for newer Macs ends in the lasting unsupported state below rather than a failure offered again every day), and its code signature is valid and satisfies `identifier "com.poliuk.join"` (`SecStaticCodeCreateWithPath`, `SecRequirementCreateWithString`, `SecStaticCodeCheckValidity` with strict validation, all architectures and nested code; else `signature`).
6. Replace the running app's bundle with `FileManager.replaceItemAt`, which swaps it atomically, and relaunch. `replaceItemAt` can throw after the swap, when it can't delete the old copy (a locked file inside it, say). So after an error Join! verifies what's at its own path: if it passes step 5 as the new version, the update is in place, and Join! removes what it can of the old copy and relaunches. Otherwise it goes on to step 7, after verifying again what it's about to reveal; if that fails, the install fails with `save`, so an unverified bundle is never revealed.
7. If the bundle's folder isn't writable, the app is running translocated, or the replace fails: move the verified app to `~/Downloads/Join <version>/Join.app` (a unique folder name if that one is taken) and reveal it in Finder. The bar says "Quit Join!, then move Join! 1.1.0 to Applications", with **Show in Finder**; if the copy isn't there any more (the user already moved it), Show in Finder puts the bar back to Install. Fixture runs reveal into `$TMPDIR/JoinUpdate/` instead and never touch ~/Downloads.

Any other error ends in `failed`, and the bar offers **Download Page**, except `unsupportedSystem` (below). The zip comes in through `URLSession`, not a browser, so it carries no quarantine attribute and the new version opens without Open Anyway. The calendar permission carries over, since every build has the same designated requirement (§13).

**A release this Mac can't run.** GitHub's API doesn't say which macOS a release needs, so one that drops this Mac's macOS is offered like any other. When step 5 finds its `LSMinimumSystemVersion` above the running macOS, `UpdateChecker` stores the version and the minimum in `Preferences.unsupportedUpdate`, clears the offer, so the update bar goes away, and sets `UpdateStatus.unsupported`: Settings reads "Join! 2.0.0 needs macOS 15.0 or later", with no Install. That survives a relaunch. A later check that finds the same release keeps it that way and doesn't offer it; a newer release clears the stored value and is offered as usual, and so does the same release once the Mac runs a macOS that's new enough. A release without a slice for this Mac's processor (`wrongArchitecture`) is a broken build rather than one for newer Macs, so it fails like any other error.

**Relaunch.** Join! starts a small `/bin/sh` loop that checks with `kill -0` every 0.2 s whether this process is still running and, once it has exited, runs `/usr/bin/open -n` on the new bundle. Then it calls `NSApp.terminate(nil)`. `-n` opens a new instance even when another copy with the same bundle identifier is running, as on a developer's Mac. A fixture run passes `--env JOIN_FIXTURE=<scenario>` (and `JOIN_FIXTURE_UPDATE`, if set) to `open`, so the relaunched copy is a fixture too.

**Trust model and its limits.**

- The trust anchor is HTTPS plus the GitHub account and its release workflow. Whoever can publish a release on Poliuk/join (the account, or a change to `release.yml` that reaches a tag on main) can put an update in front of every copy with the check on within a day, and one click on Install runs it.
- The digest comes from the same API response as the release. It catches a download that was damaged or tampered with on the way, not a release that was bad when it was published.
- The signature check pins only the designated requirement `identifier "com.poliuk.join"`, the one every build is signed with (§13). An ad-hoc signature has no certificate behind it, so anyone can sign a bundle that satisfies it: the check refuses a damaged bundle or a different app, not a forged Join!. A Developer ID requirement (with a team identifier) would close that gap; it comes with notarization.
- Only newer versions are offered, so moving `latest` back to an older release never downgrades anyone. A bad release is fixed by the next patch ([RELEASING.md](RELEASING.md)). Deleting it stops installs at once, since the download URL then fails; marking it a pre-release only stops new offers, and copies that already found it keep offering it until their next check.
- Replacing a copy in /Applications hasn't been tested under macOS's App Management protection (System Settings › Privacy & Security › App Management). If macOS refuses the replace, the install falls back to revealing the new copy (step 7).

**Why not Sparkle.** Sparkle 2 is the usual updater for apps outside the App Store, and the earlier plan was to add it if updates were wanted. But it's a third-party framework (the app has none, §1), and it needs an appcast to publish and an EdDSA key to sign every release with, kept in the release workflow's secrets. GitHub's releases API already says which release is the latest and records a SHA-256 digest for each asset, so the updater is one request plus Foundation, CryptoKit and Security. What that gives up is Sparkle's own signature: a key kept outside GitHub would stop an update published from a compromised GitHub account.

## 15. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Google → macOS Calendar sync lag (up to the user's refresh interval) | A meeting created 10 min before start may not alert | Document the refresh-interval setting; safety-net refetch; Refresh Calendars button; direct Google API as P2 if it bites. |
| `MenuBarExtra(.window)` quirks (can't dismiss programmatically, grows but never shrinks) | Panel stuck at its largest size | **Happened.** Replaced by `NSStatusItem` + `NSPopover`, and in the redesign by a borderless panel window sized from SwiftUI's measured height (§7). |
| Sizing AppKit windows from SwiftUI's measured heights | Layout loops, or a panel or Settings window stuck at the wrong size | Heights travel through preferences; the panel ignores changes under half a point; the panel and the Settings window resize on the next run-loop turn, never inside a layout pass; frames are only set when they differ. |
| macOS 14+ cooperative activation: a background app can no longer make itself active | Alert visible but Esc goes to the app the user was in | **Happened.** The alert is a non-activating panel that takes keyboard focus without activating the app (§6). The menu bar panel works the same way. |
| One-shot timers unreliable across sleep / App Nap | Missed alert | Heartbeat + overdue-fires-now rule + disabling App Nap near fire time. This is the most important correctness property; it gets the most tests. |
| Custom alert colors that are hard to read | Alert misread or ignored | Automatic colors by default, named swatches that read on every preset, contrast warnings under 4.5:1 right under the row that causes them, Join fill never below 40 %, presets, Restore Defaults. |
| A pause left on by mistake | No full-screen alerts for the rest of the day, or at all | The menu bar item shows the crossed-out bell and the panel shows a paused bar with Resume; timed pauses end on their own. **Alert me** set to **Never** is a setting, not a pause, so it shows no bell: it's a deliberate choice in Settings, and the menu bar and the panel keep working. |
| Script hooks accept notifications from any local process | Another program could pause full-screen alerts, dismiss an alert or open Settings | Only fixture runs register them, and they only do what a click could do. Nothing leaves the Mac, except an update check in a fixture run with `JOIN_FIXTURE_UPDATE=live`. They can be limited to debug builds if that ever matters. |
| No Apple Developer membership | Gatekeeper friction for users | Ship ad-hoc signed; document Open Anyway in System Settings › Privacy & Security (right-click › Open on macOS 14); updates installed from the app skip it (§14); notarize later. |
| A bad release goes out | Every copy with the update check on offers it within a day | Install refuses a damaged zip, a different app, the wrong version, or a build without this Mac's processor (§14). Delete the release: `latest` and `releases/latest/download/Join.zip` fall back to the previous one, and an Install already on offer fails at the download. Marking it a pre-release only stops new offers: copies that already found it keep offering it until their next check. Copies that installed it get the fix with the next patch ([RELEASING.md](RELEASING.md)). |
| The GitHub account or the release workflow is compromised | A forged update offered to every installed copy | Accepted for now: the identifier-only signature requirement can't tell a forged build apart (§14). A Developer ID requirement, or a signing key kept outside GitHub, would. |
| GitHub's API is down or rate-limits the check | No update offered | About one request a day per Mac; a failure only shows in Settings, and the next try waits an hour. |
| EventKit doesn't expose structured conference data | Join link missed for exotic providers | Regex table + generic `https://` fallback from location; easy community contributions. |
| `.screenSaver` window level fights with macOS lock screen / actual screen saver | Alert hidden behind lock screen | Acceptable: if the screen is locked the user isn't there. The alert remains until dismissed. |

## 16. Delivery plan

| Milestone | Scope | Exit criterion |
|---|---|---|
| **M0 Scaffold** | Xcode project, `LSUIElement`, empty `MenuBarExtra`, CI green | App runs, icon in menu bar, `xcodebuild test` passes |
| **M1 Calendars** | EventKit permission, `EventKitCalendarService`, `MeetingStore`, Calendars tab, menu bar panel with Ongoing/Upcoming | Real meetings from Google show in the panel; toggling a calendar updates the list |
| **M2 Alerts** | `AlertScheduler` + tests, `AlertCoordinator`, `AlertWindowController`, `AlertView` with countdown/dismiss/snooze, persistence of alert states | Alert fires on time on all screens, snooze/dismiss work, survives sleep/wake and relaunch |
| **M3 Settings** | General tab, Appearance tab with live preview + demo alert, `Preferences` persistence | Every setting in the brief is changeable and takes effect without restart |
| **M4 Ship** | Link detection + Join, sound, launch at login, README, CI workflow | `make run` works on a clean Mac with only the Command Line Tools |
| **M5 Redesign** | State-aware status item and borderless panel, timed pause, toolbar Settings window, new alert layout, appearance presets with automatic colors and contrast warnings, fixture calendars and script hooks | Every state drawn in the menu bar design can be reproduced with a fixture scenario or the pause hook, in light and dark |

M0–M4 were delivered in the initial implementation on 2026-10-05. M5 followed the same day.
