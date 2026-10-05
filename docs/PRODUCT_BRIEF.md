# Product Brief — Join!

*Status: approved 2026-10-05 · Open-source (MIT) macOS menu bar app*

## 1. One-liner

A free, open-source macOS menu bar app that makes calendar meetings impossible to miss: a full-screen alert a few minutes before each meeting, a menu bar preview of what's next, and one click to join the call.

Deliberately minimal: the core loop only, none of the long tail.

## 2. Problem

macOS notification banners appear in the top-right corner, are small, disappear on their own, and are trivially ignored when you are in deep focus. The result is late joins and missed meetings, especially for people with ADHD or who do long focus blocks.

The fix that works is a reminder that takes over the whole screen and stays there until you act on it.

## 3. Who it's for

- **Primary:** the author, on a Mac, using Google Calendar (work + personal), joining video calls from calendar events.
- **Secondary:** any remote worker on macOS with Google Calendar who wants a free, open tool for this.

## 4. Goals

1. Never miss a meeting: a full-screen alert fires before every accepted meeting, on time, including after the Mac has been asleep.
2. Zero-friction setup: grant calendar access, tick the calendars you care about, done.
3. Glanceable schedule: the menu bar shows what's now and what's next without opening a calendar.
4. Configurable alert: control *when* the alert fires and *how* it looks (colors, blur, opacity, buttons).
5. Stay small: a native app that idles at near-zero CPU and a few tens of MB of memory.

## 5. Non-goals (explicitly out of scope for v1)

Everything below is intentionally **not** built in v1:

- Custom reminders that are not calendar events
- Event filters (regex / keyword filters to suppress alerts)
- Global keyboard shortcuts and configurable alert shortcuts
- Theme library, theme sharing, import/export
- Desktop widgets (Notification Center)
- Apple Reminders integration
- Travel time, "Run Shortcut when joining call", privacy mode
- Menu bar title truncation options, paused-state indicators
- Per-reminder alert-time and sound overrides
- Windows / Linux / iOS

Some of these are cheap to add later; they're excluded to ship a small, solid v1.

## 6. Scope

### P0 — must ship

| # | Feature | What the user gets |
|---|---------|-------------------|
| 1 | **Calendar source** | Events from Google Calendar (see Decision 1 for how). A Calendars settings tab lists every calendar grouped by account with a checkbox to include/exclude it. All-day events and events the user has declined are ignored. |
| 2 | **Full-screen alert** | N minutes before a meeting starts, a borderless window covers every connected display (or only the main one, per setting), above every other app including full-screen apps. It shows: meeting title, time range, a live countdown ("starts in 2m 13s" / "started 1m ago"), calendar color accent, and buttons: **Join** (when a link is found), **Dismiss**, **Snooze A**, **Snooze B**, **Snooze until event**. `Esc` dismisses. Optional auto-close after X minutes. |
| 3 | **Menu bar** | A status-bar icon, optionally followed by text for the next event ("Board Meeting, in 12m"). Clicking opens a panel with **Ongoing** and **Upcoming** (Today / All toggle) sections, each row with title, time, calendar color, and a join button when a link exists. Footer: pause/resume alerts, open Settings, quit. |
| 4 | **Settings window** | Standard macOS Settings window with tabs: **General** (alert lead time in minutes, two default snooze durations, show alert on all screens vs main, auto-close alerts after N min, launch at login), **Calendars** (see #1), **Appearance** (see #5). |
| 5 | **Alert appearance** | Configure: alert text color; background blur mode (dark / light / none); optional background tint color + opacity; action-button foreground/background + opacity; primary (Join) button foreground/background + opacity. A live preview updates as values change, plus a **Show Demo Alert** button that fires a real alert with a fake event. Reset to defaults. One theme (no library). |

### P1 — should ship in v1 if cheap (they are)

| # | Feature | What the user gets |
|---|---------|-------------------|
| 6 | **One-click join** | The app scans the event's location, URL and notes for a video-call link (Google Meet, Zoom, Microsoft Teams; easy to extend) and surfaces a **Join** button in the alert and the menu bar panel. Opens in the default browser. |
| 7 | **Alert sound** | Optional system sound when the alert appears, with a "play repeatedly" toggle. Off by default. |
| 8 | **Out-of-office events** | Events titled like out-of-office blocks ("Out of office", "Fuera de la oficina", "OOO", …) don't alert unless "Alert for out-of-office events" is turned on. They still show, dimmed, in the menu bar panel. The keyword list is editable. |

### P2 — later, if wanted

Direct Google Calendar API integration (see Decision 1), multiple themes, custom reminders, event filters, Apple Reminders, keyboard shortcuts.

## 7. Key user flows

**First launch**

1. App appears in the menu bar only (no Dock icon).
2. macOS asks for Calendar access. If denied, the menu bar panel explains how to grant it in System Settings.
3. Settings → Calendars opens automatically; all calendars are on by default; the user unticks the noise (holidays, birthdays).
4. Default lead time is 3 minutes. Done.

**Meeting day**

1. Menu bar reads "Design Sync, in 9m".
2. At T-3:00 the full-screen alert appears on all screens with a countdown and a **Join** button.
3. The user clicks **Join** (opens Meet) or **Snooze 1 min** (alert returns at T-2:00) or **Dismiss**.
4. Once the meeting has started, the menu bar shows it under Ongoing with time remaining.

**Tweaking the alert**

1. Settings → Appearance. Change text color to white, blur to dark, tint 20% black.
2. Preview updates live. Click **Show Demo Alert** to see the real thing. Close it with `Esc`.

## 8. Success criteria

- The alert appears within 2 seconds of the scheduled time, including in these cases: Mac woke from sleep 30 seconds earlier; the event was created 1 minute earlier; the user is in a full-screen app on another Space.
- Events created, moved, or cancelled in Google Calendar are reflected in the app within the calendar sync interval (no app restart needed).
- Idle resource use: negligible CPU, well under 50 MB memory.
- A new user gets to a working setup in under a minute with no documentation.

## 9. Decisions

All four were settled on 2026-10-05.

| Decision | Choice | Notes |
|---|---|---|
| Calendar source | **EventKit** via the Mac's own accounts | Google accounts are added in System Settings › Internet Accounts. The direct Google Calendar API remains a P2 option behind the same `CalendarService` protocol. |
| Minimum macOS | **14 Sonoma** | Modern EventKit permission API, `@Observable`, `SMAppService`. |
| Distribution | **Unsigned** (ad-hoc signature pinned to the bundle id) | Built locally with `make run`; no Apple Developer membership needed. The calendar permission survives rebuilds. Notarization can be added later. |
| Name | **Join!** | Bundle id `com.poliuk.join`, executable `Join`. |

For the record, the alternative considered for the calendar source:

| | A. macOS Calendar / EventKit (chosen) | B. Google Calendar API directly |
|---|---|---|
| Setup for users | One permission prompt. Works for Google, iCloud, Exchange, Outlook, CalDAV. | Sign in with Google inside the app. |
| Setup for the project | None. | Google Cloud project, OAuth consent screen, and Google's verification review for the sensitive `calendar.readonly` scope (100-user cap until verified). |
| Sync latency | The account's refresh interval in Calendar.app (1 / 5 / 15 / 30 min). | Our own polling interval. |
| Meeting links | Parsed from location / notes / URL text. | Structured `conferenceData`. |
| Effort | ~1 day | ~4–5 days plus OAuth maintenance |

## 10. Rough timeline

One developer, working incrementally. Estimates are for a first usable build, not a polished release.

| Milestone | Deliverable | Est. |
|---|---|---|
| M0 | Repo, Xcode project, menu-bar-only app skeleton, CI running tests | 0.5 d |
| M1 | Calendar access + calendar picker + menu bar panel listing ongoing/upcoming | 1–2 d |
| M2 | Alert scheduler + full-screen alert window with countdown, dismiss, snooze | 2 d |
| M3 | Settings window: General + Appearance with live preview and demo alert | 2 d |
| M4 | Join-link detection, sound, launch at login, sleep/wake hardening, notarized release | 1–2 d |

Roughly 1.5 to 2 weeks of part-time work to a shareable v1.
