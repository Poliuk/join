# Technical Design — Join!

*Status: approved 2026-10-05, updated to match the implementation after the redesign · Companion to PRODUCT_BRIEF.md*

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
│  in MenuBarPanelWindow    in one AlertWindow    Appearance panes in │
│  (StatusItemController)   per target screen     SettingsWindow…     │
└──────────┬────────────────────────┬──────────────────────┬──────────┘
           │                        │                      │
┌──────────▼────────────────────────▼──────────────────────▼──────────┐
│  App state (@Observable, @MainActor)                                │
│  AppModel: wiring, and a clock that ticks on :00 and :30            │
│  MeetingStore       AlertCoordinator             Preferences        │
│  (meetings, sync)   (schedule/present/snooze/    (UserDefaults-     │
│                      dismiss, PauseState)         backed)           │
└──────────┬────────────────────────┬─────────────────────────────────┘
           │                        │
┌──────────▼──────────┐ ┌───────────▼───────────────┐ ┌───────────────────────┐
│ CalendarService     │ │ JoinCore (pure, tested)   │ │ AlertWindowController │
│ (protocol)          │ │ AlertScheduler            │ │ (AppKit, one NSPanel  │
│ └ EventKitCal…      │ │ MenuBarPresenter          │ │  per target screen)   │
│ └ FixtureCal… (dev) │ │ PanelPresenter            │ └───────────────────────┘
│ └ (later) Google    │ │ AlertCountdown, palette   │
└─────────────────────┘ └───────────────────────────┘
        │
   EventKit (EKEventStore)  ← Google account via System Settings › Internet Accounts
```

Principles:

- **One source of truth for meetings.** `MeetingStore` owns `[Meeting]`; everything else reads from it.
- **Scheduling is pure.** `AlertScheduler` takes `(meetings, alertStates, leadTime, isPaused, now)` and returns the next thing to do. No timers, no windows. Fully unit-testable.
- **Presentation is pure too.** What the menu bar item says, what the panel lists, the alert's countdown wording and the alert's resolved colors are computed in `JoinCore` (`MenuBarPresenter`, `PanelPresenter`, `LocationFormatter`, `AlertCountdown`, `AlertAppearance.palette`, `SettingsOptions`) from plain values and a `now`. The SwiftUI views only lay the results out.
- **Side effects live at the edges.** `AlertCoordinator` owns the timer and calls the scheduler; `AlertWindowController` and `StatusItemController` own windows.
- **Calendar backend is swappable.** `CalendarService` is a protocol. Besides EventKit there is a fixture implementation for checking the UI (§12), and a direct Google API implementation can be dropped in later.

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
    var myStatus: ParticipationStatus    // accepted, tentative, declined, unknown
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

final class Preferences {                  // @Observable, persisted in UserDefaults
    var leadTime: TimeInterval = 180       // always whole minutes
    var snoozeDurations: [TimeInterval] = [60, 300]   // exactly two
    var alertScreens: AlertScreens = .all  // .all, .main, .pointer
    var autoCloseEnabled = true
    var autoCloseAfter: TimeInterval = 15 * 60
    var soundName: String? = nil
    var soundRepeats = false
    var enabledCalendarIDs: Set<String>?   // nil = never chosen → all
    var menuBarShowsNextEvent = true
    var menuBarShowsEventTitles = false
    var alertForOutOfOffice = false        // see §9a
    var outOfOfficeKeywords: [String]
    var appearance: AlertAppearance
}

struct AlertAppearance: Codable, Hashable {   // saved as JSON with "version": 2
    var blurMode: BlurMode            // .dark, .light (.none only from old saves)
    var tint: RGBA?                   // nil = no tint
    var tintStrength: Double          // 0...1, kept while the tint is off
    var textColor: RGBA?              // nil = Automatic
    var join: AlertButtonColors
    var dismissAndSnooze: AlertButtonColors
    static let `default` = AlertAppearancePreset.dark.appearance
}

struct AlertButtonColors: Codable, Hashable {
    var text: RGBA?                   // nil = Automatic
    var fill: RGBA?                   // nil = Automatic
    var fillOpacity: Double           // scales the fill; Join 0.4...1, others 0...1
}
```

Launch at login is not a preference: it is read from and written to `SMAppService` directly. The pause state is stored by `AlertCoordinator` next to the alert states (§5).

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

After fetching, `MeetingStore` fills `joinURL` (§9) and `isOutOfOffice` (§9a) on each meeting.

**Staying fresh.** Refetch on:

- `NSNotification.Name.EKEventStoreChanged` (fires when the system calendar database changes, including after a Google sync),
- `NSWorkspace.didWakeNotification`,
- a change to `enabledCalendarIDs` or `outOfOfficeKeywords`,
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
5. If reminders are **paused** (`PauseState.isPaused(at: now)`), return nil. When a pause ends, rule 1 applies as usual: a meeting that is about to start, or started less than 5 minutes ago, alerts right away.

The meetings passed in are `MeetingStore.alertableMeetings`: all meetings, minus out-of-office blocks unless the user turned them on.

`AlertCoordinator` (side effects):

- Holds one `DispatchSourceTimer`. On every re-plan it cancels and re-arms the timer for `plan.fireAt`, with 0.5 s leeway.
- Also runs a 30-second **heartbeat** that re-plans and fires anything overdue. This catches the cases where a one-shot timer silently fails: system sleep, clock/timezone change, the process being suspended by App Nap (which we also disable via `ProcessInfo.beginActivity(.userInitiatedAllowingIdleSystemSleep)` while an alert is pending within 5 minutes). The heartbeat is also what ends an expired timed pause.
- Schedules nothing until `start()` is called. Fixture runs (§12) never call it, so they can't alert.
- On fire: mark meetings `.showing`, ask `AlertWindowController` to present on the screens chosen in `Preferences.alertScreens`, play the sound, start the auto-close timer if configured.
- User actions from the alert: Dismiss → `.dismissed`; Snooze(d) → `.snoozed(until: now + d)`; **At \<time\>** → `.snoozed(until: start)`, or `.dismissed` if the meeting has already started; Join → open URL then `.dismissed`.
- `AlertState`s are persisted (`UserDefaults`, each with the meeting's end as expiry, pruned when expired) so a relaunch during a snooze doesn't re-alert or lose the snooze.
- **Pause.** `pause(_ option: PauseOption)` turns "1 hour", "until tomorrow" (local midnight) or "until I resume" into a `PauseState`; `resume()` sets `.active`. The state is saved as JSON under `pauseState`, so "Pause until tomorrow" survives a relaunch. A timed pause that has run out collapses to `.active` on load and on the next re-plan.
- One alert at a time: while an alert is on screen, nothing else fires; the next plan is computed when it closes.
- If a meeting is edited (start moves) its `id` changes → new occurrence, state resets to `.pending`. Cancelled meetings disappear from the store; if their alert is showing, the window closes.
- `showDemoAlert()` presents a fake meeting starting 3 minutes out (on a whole second, so the countdown starts at 3:00). Its buttons only close it. It is refused, and the Settings button is disabled, while a real alert is on screen (`isAlerting`); a real alert that fires during a demo replaces it.
- `willPresentAlert` runs right before any alert (real or demo) is presented. The app uses it to close the menu bar panel, including a header menu that is open, so the panel can't take keyboard focus back from the alert.

## 6. Alert window (AppKit)

One `AlertWindow` (an `NSPanel`) per target screen. `Preferences.alertScreens` picks them: every `NSScreen` (`.all`), `NSScreen.main` (`.main`), or the screen under the mouse pointer when the alert fires (`.pointer`). Recreated on `NSApplication.didChangeScreenParametersNotification` (display hot-plug while showing).

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
6. The snooze row: a "Snooze" label, one button per snooze duration ("1 min", "5 min", "1 hr", worded like Settings), and **At event start**, which snoozes until the meeting starts (VoiceOver: "Snooze until the event starts at 2:00 PM"). It is left out once the start has passed. The design's "At 2:00 PM" was renamed at the user's request.
7. **Dismiss**, with an `esc` key hint.

When several meetings share one plan, each gets its own calendar, countdown, title and details block (titles at 40 pt), above a single button group; the Join button names the meeting it joins ("Join Design Sync"). If the blocks don't fit the screen they scroll, with a fade at the edges, while the button group keeps its place, so Join, snooze and Dismiss always stay reachable. The hosting view has no sizing constraints, so the alert never grows past a small screen. A demo alert adds the line "This is a demo alert. Press Esc to close it."

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
- Join: the fill defaults to amber `#F5A524`. The automatic label is white or near-black, whichever reads better on the fill.
- Dismiss & Snooze: the automatic fill is white at 16 % on a dark backdrop and black at 7 % on a light one. The automatic label is chosen by contrast, like Join's.
- Each button kind's fill opacity scales its fill, automatic or custom. Join's is limited to 40–100 % so the main action never disappears; Dismiss & Snooze goes from 0 to 100 %.
- `material`: the layer the blur adds over the desktop. Only the Settings preview draws it, because a window can't blur what is behind it inside itself.

`contrastWarnings` checks the event text, the Join label and the Dismiss & Snooze labels against their composited backgrounds. Each one under 4.5:1 (WCAG AA for body text) gets a warning with its ratio, rounded down so 4.46 reads "4.4:1", never "4.5:1".

Presets (`AlertAppearancePreset`):

| Preset | Backdrop | Tint | Join | Dismiss & Snooze |
|---|---|---|---|---|
| Dark (default) | dark blur | none | amber, automatic label | automatic |
| Light | light blur | none | amber, automatic label | automatic |
| High contrast | dark blur | black at 70 % | `#FFD60A`, black label | white at 22 % |
| Midnight | dark blur | `#1E3A8A` at 45 % | `#2563EB`, automatic label | automatic |

`matchingPreset` compares appearances the way a person sees them: colors at 8 bits, opacities in whole percent, tint strength ignored while the tint is off. Settings uses it to outline the active preset or say "Custom". Switching a color from Automatic to Custom starts from the color currently shown, so nothing changes until the user picks a new one. The Dismiss & Snooze fill converts its opacity in both directions, so switching back and forth keeps the look.

**Saved format.** The appearance is encoded as JSON with `"version": 2`; missing keys fall back to the default. JSON without a version is the shape saved before the redesign, where every color was explicit (`textColor`, `backgroundTint` + `backgroundOpacity`, `button*` and `primary*` colors and opacities). An untouched old default becomes the new default. Anything customized keeps its exact colors: the background tint and opacity become `tint` and `tintStrength`, the primary button becomes Join (opacity clamped to 40–100 %), and the other buttons become Dismiss & Snooze. An old "No blur" survives, and only then does Settings offer it in the Backdrop pop-up.

## 7. Menu bar

`StatusItemController` owns an `NSStatusItem` and a `MenuBarPanelWindow`. SwiftUI's `MenuBarExtra` was used first and dropped: its window grows with its content but never shrinks, and it can't be closed programmatically. An `NSPopover` replaced it until the redesign, which called for a borderless panel with its own corners and material and no arrow. SwiftUI still requires one scene, so `JoinApp` declares a `MenuBarExtra` with `isInserted: .constant(false)`, which keeps SwiftUI's standard Edit menu (copy and paste in text fields) without adding UI.

**Status item.** `MenuBarPresenter.status(...)` (JoinCore) returns a `MenuBarStatus`: a kind, optional text and an accessibility label. Its inputs are the alertable meetings (so out-of-office blocks count only when the user opted in), `now`, the `PauseState`, `menuBarShowsNextEvent` and `menuBarShowsEventTitles`. Precedence: paused > starting soon > in a meeting > within the hour > later.

| Kind | When | Drawn as |
|---|---|---|
| idle | nothing upcoming in the 7-day window | `calendar` symbol alone |
| later | next meeting more than an hour away | `calendar` + a countdown later today ("Next in 11 h 40 min"), otherwise the day and time: "Tomorrow at 1:00 PM", "In 3 days at 9:10 AM" (calendar days). The user chose this over the design's "1:00 PM" / "Tomorrow 1:00 PM" / weekday. VoiceOver: "in 11 hours 40 minutes, at 1:00 PM", "tomorrow at 1:00 PM", "in 3 days, Thursday at 9:10 AM" |
| withinHour | next meeting within the hour | `calendar` + "Next in 42 min" |
| startingSoon | next meeting in 5 minutes or less | a pill filled with the system accent color: white `video.fill` icon + "Next in 4 min" |
| inMeeting | in a meeting (the one that started most recently) | a 16 pt ring that drains from full to empty over the meeting + "40 min left" |
| paused | reminders paused | `bell.slash` alone, never text |

- Starting soon wins over a meeting in progress, so the next call shows while you are still in the previous one.
- Durations are whole minutes rounded up, so "0 min" never shows before a start. Time left beyond an hour reads "2 h 15 min".
- Settings › General › **Menu bar** picks one of three (`MenuBarDisplay`, stored as `menuBarShowsNextEvent` and `menuBarShowsEventTitles`): **Icon only**, **Time until next event** (the default), or **Title and time until next event**. Without a title a countdown starts with "Next" ("Next in 42 min"); with one, the title takes its place, truncated to 24 characters: "Product Planning · in 4 min".
- With **Icon only**, the item has no text but keeps its state icon (pill, ring, bell).
- Plain states use template images, so the menu bar tints them. The pill is drawn in full color, and redrawn when the system colors change. Text uses a monospaced-digit font, and countdowns past an hour always show two-digit minutes ("11 h 05 min", "2 h 00 min left", `MenuBarPresenter.steadyDuration`), so the item keeps its width as the minutes tick instead of nudging every other menu bar item each hour. The panel keeps the shorter "2 h".
- The button re-renders through observation tracking whenever `AppModel.menuBarStatus` changes. `AppModel.now` ticks on every :00 and :30 of the clock, so countdowns stay in step with meetings, which start on whole minutes.
- VoiceOver reads full words: "Join!: Product Planning starts in 4 minutes".

**Panel window.** `MenuBarPanelWindow` is a borderless, non-activating `NSPanel` at `.statusBar` level, 368 pt wide, on all Spaces. Like the alert, it takes Esc and Return without pulling the user's app out of the foreground. Its background is the system menus' material, so the panel reads like a native menu in light and dark mode: on macOS 26 and later an `NSGlassEffectView` (Liquid Glass, 14 pt corners), looked up at runtime because the SDK the app builds against predates it, and set up only through its public `cornerRadius` and `contentView`; before that an `NSVisualEffectView` with the `.menu` material and a rounded mask image, which shapes both the blur and the window shadow. Nothing is laid over the material, so the desktop's colors show through as they do in a menu. The SwiftUI view sits in an `NSHostingView` that accepts the first click.

**Sizing.** `MenuBarPanelView` measures its header and its body with `GeometryReader` preferences and reports the sum through `MenuBarPanelContext`. The controller hangs the panel 6 pt below the status item with the top edge fixed, and sets the height to that natural height, capped at 640 pt and at the room left above the bottom of the screen (minus an 8 pt margin). The x position follows the item and is nudged to stay on screen. The resize runs on the next run-loop turn, because resizing the window from inside a SwiftUI layout pass re-enters layout. When the content is taller than the panel, the body scrolls and a 46 pt fade at the bottom shows there is more. The fade's strength follows how much is still hidden, so it is gone at the end of the list.

**Closing and keys.** The panel closes on Esc, ⌘W, a second click on the item, a click anywhere else (global and local event monitors), the app resigning active, another window becoming key (except while one of the panel's own menus is open), a Space change and a display change. It also closes before Join, Directions, Settings or Open System Settings open anything, and before any alert appears. ⌘, opens Settings and ⌘Q quits. Return runs the hero card's button when the hero is Starting soon or Now.

**Panel content.** `PanelPresenter.content(meetings:alertable:now:showsOutOfOffice:)` (JoinCore) returns one hero card and a list of sections. The views draw them with `PanelColors`, light/dark pairs with translucent fills that sit on the material in either mode.

- **Header:** today's date ("Tuesday, 6 October", localized), a "Fixture" badge in fixture runs (§12), the bell button and the gear menu. The panel window's accessible name is "Join! meetings".
- **Paused bar**, while paused: "Reminders paused until 11:50 AM", "… until tomorrow" or "Reminders paused", with **Resume**.
- **Hero**, exactly one, chosen from the alertable meetings:
  - **Starting soon**, when the next start is 5 minutes or less away: accent-tinted card, "Starts in 4 min", accent button. Wins over Now.
  - **Now**, the meeting you are in: "Now · 40 min left", a progress bar in the calendar color, accent button.
  - **Next**, the next meeting later today: neutral card, "Next · in 2 h 15 min", neutral button.
  - **No more meetings today**, with "Next up tomorrow at 1:00 PM, in 15 h 30 min" (the countdown is dropped a day or more ahead) or "Nothing in the next 7 days".
  - Meeting cards show the label, the time range, the title with a calendar-color dot, the short location and any overlap (for meetings that haven't started), and the action button.
- **Sections** below the hero leave out the hero's meeting, anything that has ended, and out-of-office blocks when **Show out-of-office events in the list** is off:
  - **Now** (titled **Also now** when the hero is a Now card): other ongoing meetings, out-of-office blocks included unless that switch is off.
  - **Later today.**
  - One section per following day in the 7-day window: **Tomorrow** Wed 7 Oct, then **Wednesday** 7 Oct (localized).
- **Rows:** start over end time, a calendar-color bar, the title, at most one detail line, and an icon button. The icon button's fill brightens under the pointer (0.12 s ease, none with Reduce Motion) and the cursor becomes a pointing hand. The detail is, in this order: a progress bar with "3 h 10 min left" for a running meeting, an amber "Overlaps Workshop", or a pin with the short location.
- **Out-of-office rows** are striped and muted, with no detail and no button.
- **Overlaps.** A meeting that starts while an earlier one is still running is flagged with the latest-ending of those. Only the later meeting of a pair is flagged, and out-of-office blocks never count. On a card the warning also says until when: "Overlaps Workshop, which runs until 7:30 PM".
- **Actions.** Join (video icon) when a join link was found. Otherwise **Directions** when the meeting is in person: its location names a physical place. `LocationFormatter.physicalPlace(in:)` splits the location on ";" and new lines and drops the virtual parts: links with or without a scheme ("meet.google.com/…"), phone numbers and dial-ins, bare service names ("Teams", "Zoom", "Online", …). "Sala Retiro; Microsoft Teams Meeting" keeps "Sala Retiro"; "Teams Room 3" stays a place. Directions opens Apple Maps (`https://maps.apple.com/?daddr=…`).
- **Locations.** `LocationFormatter` shortens the physical part for rows and cards. It finds the street first (a component followed by a house number, or one that starts with a number), then shows "name · locality" or "street · locality": "C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España" → "C. de Ruiz de Alarcón, 23 · Retiro"; "Museo del Prado, C. de Ruiz de Alarcón, 23, Retiro, 28014 Madrid, España" → "Museo del Prado · Retiro"; "1 Infinite Loop" over "Cupertino, CA 95014" → "1 Infinite Loop · Cupertino".

**Header menus.** Both are AppKit `NSMenu`s that pop up below their 28 pt button, right edges aligned.

- **Bell:** while active, a menu: "Pause for 1 hour", "Pause until tomorrow", "Pause until I resume" (VoiceOver: "Pause reminders", hint "Opens a menu"). The choice goes to `AlertCoordinator.pause(_:)`, which persists it (§5). While paused the button shows `bell.slash`, is drawn pressed (selected for VoiceOver), is labelled "Resume reminders", and resumes directly, as in the Paused artboard.
- **Gear** (`gearshape`, VoiceOver "Settings", hint "Opens a menu"): "Settings ⌘,", "Quit Join! ⌘Q". The design's ⋯ menu and its Open Calendar item were dropped at the user's request.

**No permission.** Without calendar access the panel shows an explanation, **Open System Settings** (`x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars`) and **Check Again**.

## 8. Settings window

Dependent settings (Repeat until the alert is closed, Custom time, Tint strength) are drawn as children of the row above: indented 30 pt, with their hairline starting at the indent and an elbow line running from under the parent's label to their own (`SettingsRow(indented:)`).

`SettingsWindowController` owns a plain AppKit window whose content view controller is an `NSTabViewController` with `tabStyle = .toolbar`: one toolbar item per pane, **General** (`gearshape`), **Calendars** (`calendar`) and **Appearance** (`circle.righthalf.filled`). SwiftUI's `Settings` scene can't be opened dependably from a menu-bar-only app. The window uses `toolbarStyle = .preference`, takes the selected pane's title, can be closed but not resized, and crossfades between panes. It opens from the gear menu, ⌘, in the panel, reopening the app (`applicationShouldHandleReopen`), or the `openSettings` script hook (§12), which can also pick the pane.

**Sizing.** Each pane is a SwiftUI view in an `NSHostingView` with `sizingOptions = []`, wrapped in `SettingsPaneScroll`, which reports the content's natural height through a preference. The window keeps a 720 pt content width and takes the selected pane's height. It animates when switching panes. A height change from within a pane (a preset adding the Tint strength row, say) resizes it without animation on the next run-loop turn: SwiftUI reports the new height from inside its layout pass, and resizing the window there left the window's content view out of step with its frame by the height change, so the pane slid under the toolbar or below a gap. It keeps its top edge in place and stays on screen. It only scrolls when the screen is too short for the pane.

**Focus.** Opening the window, switching panes and closing the window all clear the first responder. That stops AppKit from focusing the first text field on open, and commits a half-typed value the same way as when the field loses focus.

**Components.** `SettingsComponents.swift` holds the shared building blocks, so the three panes look alike: `SettingsPalette` (window, box, separator, chip, field and connector colors as light/dark pairs), `SettingsMetrics` (pane width, padding, indent), `SettingsSection` (a heading over a box), `SettingsBox` (the rounded group), `SettingsRow` (label left, control right, a hairline above, secondary or disabled tone, and an optional indent for dependent rows, which insets the hairline and draws an elbow connector in the gutter), `SettingsSwitchRow`, `SettingsChip`, `SettingsFlowLayout` (a wrapping layout for tokens, where a subview tagged `SettingsFlowFill` takes the rest of its line) and `SettingsPaneScroll`. The pop-up choices and their labels come from `SettingsOptions` in JoinCore. All controls bind to `Preferences`.

- **General:**
  - Top box: **Open at login** (`SMAppService.mainApp.register()` / `.unregister()`; if macOS wants approval, a hint points to System Settings › General › Login Items; switch and hint are re-read whenever the app becomes active or Settings becomes key, so the hint clears after approval; in a fixture run the row is disabled, "Not available in fixture mode.", and never touches `SMAppService`), and **Menu bar** (Icon only, Time until next event, Title and time until next event), one pop-up in place of the design's two switches.
  - **Alert:** **Alert me**: When the event starts, 1, 2, 3, 5 or 10 minutes before, or Custom…. Custom shows an indented row with a minutes field and a stepper (0–120). The field saves on Return or when it loses focus, never mid-typing, so "3" → "35" → "5" can't briefly mean 35 minutes and fire alerts early. A stored lead time that isn't a preset opens as Custom. **Show alert on**: All screens, Main screen only, Screen with the pointer. **Sound**: a play button and a pop-up with None and the `/System/Library/Sounds` names. The indented **Repeat until the alert is closed** is disabled without a sound.
  - **Out of office** (§9a): **Alert for out-of-office events**, off by default; **Show out-of-office events in the list**, on by default (off leaves them out of the panel's lists); and **Title keywords** as removable tokens. Return or a comma adds a keyword, Delete in the empty field removes the last one, leaving the field adds what was typed, and duplicates are ignored regardless of case. **Restore Defaults** brings back the built-in list. The settings design put this section on Calendars; it lives on General by the user's choice.
  - **Snooze & auto-close:** **First snooze button** and **Second snooze button** (1, 2, 3, 5, 10, 15, 30 or 60 minutes; a stored value outside that list stays selectable) and **Close alerts automatically** (Never, or after 5, 10, 15, 30 or 60 minutes). Under the box, "The alert offers" with chips that mirror the alert's snooze row: "1 min", "5 min", "At event start".
- **Calendars:** a line saying alerts come from the checked calendars, with "N of M selected", and an orange warning when none are selected ("you won't get any alerts"). One group per account (`calendar.source.title`) with its own "N of M" and a **Select All** / **Deselect All** link when it has more than one calendar. Each calendar is a checkbox filled with the calendar's color; VoiceOver sees a standard checkbox. The first change turns the implicit "all calendars" (`nil`) into an explicit set. Footer: where to add a missing account and where the sync interval is set, an "Updated just now" / "Updated 5 minutes ago" label from `MeetingStore.lastRefreshed`, **Open Internet Accounts…** and **Refresh Calendars**, which re-reads EventKit. Without calendar access the pane shows a permission prompt instead.
- **Appearance:**
  - A live preview at the top: the real `AlertContentView` at 52 % scale, with a sample meeting frozen at "Starts in 2:59", over a sample screen picked with **Preview on**: Wallpaper, Light app or Dark app. A window can't blur what is behind it inside itself, so the sample screen is drawn already blurred, and the palette's `material` is laid over it as a plain layer, then the tint and scrim as on the real alert. **Show Demo Alert** fires a real full-screen alert with a fake event.
  - **Style:** one card per preset (Dark, Light, High contrast, Midnight), drawn as a miniature. The matching preset is outlined; "Custom" shows when none matches.
  - **Alert:** **Backdrop** (Dark blur, Light blur; No blur only for an old saved theme), **Tint** (None, or Custom with a color well), **Tint strength** (a percent slider, while tinted) and **Text color** (Automatic, or Custom with a well). Contrast warnings for the event text appear under the box.
  - **Buttons:** a table with the columns Text, Fill and Fill opacity, and one row each for **Join** and **Dismiss & Snooze**. Each color is Automatic or Custom with a well. Contrast warnings for the button labels appear under the box.
  - **Restore Defaults**, disabled while the appearance already equals the default.

**Persistence.** `Preferences` is an `@Observable` class whose stored properties read/write `UserDefaults` (theme encoded as JSON `Data`). No `@AppStorage` scattered across views; one owner. Values stored by older builds are migrated on load:

- Lead times with seconds are rounded to whole minutes. Every write is rounded too.
- The old `showOnAllScreens` Bool becomes `alertScreens`: true → all screens, false → main screen. Writing the new key removes the old one.
- The old inverted `skipOutOfOffice` flag becomes `alertForOutOfOffice`, the same way.
- `menuBarShowsEventTitles` is new and starts off. Builds before the redesign always showed the title.
- The appearance JSON migrates as described in §6.

## 9a. Out-of-office events

EventKit doesn't expose Google's "out of office" event type, but Google titles those events predictably in the account's language ("Out of office", "Fuera de la oficina", …). `OutOfOfficeDetector` matches the title against a keyword list (short tokens like "OOO" and "PTO" must stand alone). Unless **Alert for out-of-office events** is on (Settings › General › Out of office), matching events never alert and don't drive the menu bar item or the panel's hero card. They appear in the panel's lists as striped, muted rows with no button unless **Show out-of-office events in the list** is off, and they never count as overlaps.

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
| Two meetings at the same time | One alert listing both. |
| Next meeting starts while you're in one | In its last 5 minutes it takes over the menu bar item (pill) and the panel's hero card; the ongoing one moves to "Now". |
| Two meetings overlap | The later one is flagged in the panel ("Overlaps …"); both alert normally. |
| Meeting runs past midnight | Time range reads "11:30 PM – 12:30 AM"; longer than a day, "Mon 9:00 AM – Wed 5:00 PM". `DateIntervalFormatter` alone prints full dates as soon as a range crosses midnight. |
| Lead time changed in Settings | Re-plan; a meeting already `.dismissed` stays dismissed. |
| Paused until tomorrow, then the app relaunches | The pause is read back from UserDefaults; an expired one is dropped. |
| A timed pause runs out | The next heartbeat (≤ 30 s) clears it; a meeting about to start alerts right away. |
| User in a full-screen app on another Space | `.canJoinAllSpaces` + `.fullScreenAuxiliary` + `.screenSaver` level shows over it. |
| Display plugged/unplugged during alert | Windows rebuilt from current `NSScreen.screens` (for "Screen with the pointer", the screen the pointer is on at that moment). |
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
│   │   Meeting, AlertState, AlertScheduler, AlertScreens, PauseState,
│   │   MeetingLinkDetector, OutOfOfficeDetector, MeetingTimeFormatter,
│   │   MenuBarPresenter, PanelPresenter, LocationFormatter, AlertCountdown,
│   │   AlertAppearance (presets, palette, contrast), RGBA, SettingsOptions,
│   │   Preferences
│   └── Join/                The app
│       ├── App/             JoinApp (scenes), AppDelegate (script hooks), AppModel (wiring, clock)
│       ├── Calendar/        CalendarService (protocol), EventKitCalendarService,
│       │                    FixtureCalendarService, MeetingStore
│       ├── Alerts/          AlertCoordinator, AlertWindowController, AlertView
│       ├── MenuBar/         StatusItemController, StatusItemImages, MenuBarPanelWindow,
│       │                    MenuBarPanelView, PanelHeroView, PanelRowView, PanelStyle
│       ├── Settings/        SettingsWindowController, SettingsComponents, GeneralTab,
│       │                    OutOfOfficeSection, CalendarsTab, AppearanceTab, AppearancePreview
│       └── Support/         Observation helper, Color↔RGBA, SystemSounds, LaunchAtLogin,
│                            WindowSnapshots
├── Tests/JoinCoreTests/     XCTest suites for everything in JoinCore
├── Resources/Info.plist     LSUIElement, usage description, bundle metadata
├── scripts/build-app.sh     Assembles build/Join.app and signs it (see §13)
├── Makefile                 make app | run | test | clean
├── .github/workflows/ci.yml build + test + package on macos-14
└── docs/                    This document and the product brief
```

Bundle id `com.poliuk.join`, `LSUIElement = YES`.

## 12. Testing strategy

- **Unit tests (XCTest) on `JoinCore`:**
  - `AlertScheduler` (every row of the edge-case table above with a fixed `now`), `MeetingLinkDetector` (one fixture per provider plus negatives), `MeetingFilter`, `OutOfOfficeDetector`.
  - `MeetingTimeFormatter`, including ranges across midnight and longer than a day.
  - `MenuBarPresenter` (every status item state, precedence, titles on and off, durations, the paused message, the header date), `PanelPresenter` (each hero, the rows drawn in the design, day headings, overlaps, out-of-office rows, ended meetings left out), `LocationFormatter` (short locations, physical places, in person, directions URL), `AlertCountdown` (phases, texts, snooze labels), `PauseState`.
  - `AlertAppearance`: `RGBA` hex, compositing and contrast; JSON round-trip; legacy JSON migration; presets and preset matching; automatic colors; contrast warnings; switching between Automatic and Custom.
  - `Preferences` round-trip through an isolated `UserDefaults` suite, plus each migration in §8. `SettingsOptions`: pop-up choices, the "Updated" label, calendar selection, keyword tokens.
  - `MenuBarFixtures` holds the week drawn in the menu bar design (Monday 5 – Thursday 8 October 2026) in UTC, with `en_US` and `en_GB` locales, so the presenter tests check the design's exact strings and don't depend on the machine's time zone.
- `swift test` needs XCTest, which ships with Xcode, not with the Command Line Tools. CI runs the suite on every push. Locally without Xcode the suite can't run; `swift build` still works.
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
  | `denied` | calendar access denied, so the permission prompts show |

  `JOIN_SETTINGS_MAX_HEIGHT=<points>` (fixture runs only) caps the Settings window's content height, to check the scrolling layout of a short screen on a tall one.

  `JOIN_FIXTURE_REGULAR=1` (fixture runs only) gives Join! a Dock icon and a menu bar of its own, so UI automation tools that only see regular apps can click through Settings. Some bugs only show up with real clicks, not with the script hooks below.

  Every scenario has the same following days: an out-of-office block, an in-person appointment, two overlapping calls, and more meetings on the two days after. Five calendars in two accounts fill the Calendars pane. Times are relative to launch, rounded to the minute. Only these five names turn fixture mode on; any other value is logged and ignored, so a typo launches the real app. A fixture run uses its own defaults domain (`com.poliuk.join.fixture`), so it can't change real settings, never starts the alert scheduler, so it can't put an alert on screen by itself, and leaves the login item alone. It shows a "Fixture" marker in the panel header and the Settings title, and it quits after two hours so a forgotten one can't silence real alerts for long. Show Demo Alert still works. Quit a running Join! first: `open` hands the request to the running copy instead of starting a new one, and the variable is lost.
- **Script hooks.** To drive a fixture run from scripts without clicking, `AppDelegate` listens for distributed notifications named `com.poliuk.join.fixture.<hook>`. Only fixture runs register them: any process can post a distributed notification, so a normal run must not let one pause, dismiss or capture the real app. The notification's object, when present, is the argument.

  | Hook | Argument | Does |
  |---|---|---|
  | `openSettings` | `general`, `calendars` or `appearance` (optional) | opens Settings, on that pane if given |
  | `snapshot` | a folder name (default `latest`) | writes a PNG of every visible window of the app (`NN-<window class>-<title>.png`) into `$TMPDIR/JoinSnapshots/<name>`, without screen-recording permission; the name is reduced to one safe path component |
  | `showDemoAlert` | – | shows the demo alert |
  | `dismissAlert` | – | dismisses the alert on screen, like clicking Dismiss |
  | `togglePanel` | – | opens or closes the menu bar panel |
  | `pause` | `oneHour`, `untilTomorrow` or `untilResumed` | pauses reminders; ignored without a valid option |
  | `resume` | – | resumes reminders |
  | `appearance` | `light`, `dark`, anything else follows the system | forces the app's light or dark appearance |
  | `preset` | `dark`, `light`, `highContrast` or `midnight` | applies an alert style preset, as clicking its card in Appearance does |

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

- **Manual smoke checklist** for the UI: each fixture scenario in light and dark; a long panel (scrolling and fade); pause and resume, including across a relaunch; the demo alert with each preset, on all screens, the main screen and the pointer's screen; snooze and "At event start"; full-screen app on another Space; sleep/wake with a meeting 2 minutes out.
- **No UI tests**; the AppKit window behaviour isn't meaningfully testable headless.

## 13. Build, CI, distribution

- **Build:** `make app` runs `scripts/build-app.sh`: `swift build -c release`, copies the binary and `Info.plist` into `build/Join.app`, and ad-hoc signs it with an explicit designated requirement, `identifier "com.poliuk.join"`. A plain ad-hoc signature's requirement is the hash of that exact binary, so TCC treated every rebuild as a new app and asked for calendar access again. Pinning the requirement to the bundle identifier keeps the grant across rebuilds. The trade-off: any locally built binary that claims that identifier inherits the grant, which is acceptable for a locally built app and goes away with a real signing identity. `make run` builds and opens it.
- **CI:** GitHub Actions on `macos-14`: `swift build`, `swift test`, `scripts/build-app.sh`, and the `.app` is uploaded as a workflow artifact.
- **Distribution:** unsigned/un-notarized by decision. Users build locally or download the CI artifact and right-click → Open once. Notarization (Developer ID + `notarytool`) can be added to `release.yml` later without touching the app.
- **Sandbox:** off. Sandboxing requires a real signing identity to be meaningful; nothing in the app needs it.
- **Auto-update:** not in v1. Sparkle 2 if wanted later.

## 14. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Google → macOS Calendar sync lag (up to the user's refresh interval) | A meeting created 10 min before start may not alert | Document the refresh-interval setting; safety-net refetch; Refresh Calendars button; direct Google API as P2 if it bites. |
| `MenuBarExtra(.window)` quirks (can't dismiss programmatically, grows but never shrinks) | Panel stuck at its largest size | **Happened.** Replaced by `NSStatusItem` + `NSPopover`, and in the redesign by a borderless panel window sized from SwiftUI's measured height (§7). |
| Sizing AppKit windows from SwiftUI's measured heights | Layout loops, or a panel or Settings window stuck at the wrong size | Heights travel through preferences; the panel ignores changes under half a point; the panel and the Settings window resize on the next run-loop turn, never inside a layout pass; frames are only set when they differ. |
| macOS 14+ cooperative activation: a background app can no longer make itself active | Alert visible but Esc goes to the app the user was in | **Happened.** The alert is a non-activating panel that takes keyboard focus without activating the app (§6). The menu bar panel works the same way. |
| One-shot timers unreliable across sleep / App Nap | Missed alert | Heartbeat + overdue-fires-now rule + disabling App Nap near fire time. This is the most important correctness property; it gets the most tests. |
| Custom alert colors that are hard to read | Alert misread or ignored | Automatic colors by default, contrast warnings under 4.5:1, Join fill never below 40 %, presets, Restore Defaults. |
| A pause left on by mistake | No alerts for the rest of the day, or at all | The menu bar item shows the crossed-out bell and the panel shows a paused bar with Resume; timed pauses end on their own. |
| Script hooks accept notifications from any local process | Another program could pause reminders, dismiss an alert or open Settings | They only do what a click could do, and nothing leaves the Mac. They can be limited to debug builds if that ever matters. |
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
| **M5 Redesign** | State-aware status item and borderless panel, timed pause, toolbar Settings window, new alert layout, appearance presets with automatic colors and contrast warnings, fixture calendars and script hooks | Every state drawn in the menu bar design can be reproduced with a fixture scenario or the pause hook, in light and dark |

M0–M4 were delivered in the initial implementation on 2026-10-05. M5 followed the same day.
