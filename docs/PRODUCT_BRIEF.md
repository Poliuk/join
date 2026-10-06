# Product Brief — Join!

*Status: approved 2026-10-05, updated after the redesign · Open-source (MIT) macOS menu bar app*

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
3. Glanceable schedule: the menu bar item shows how long until the next meeting, or how long the current one has left, and its panel shows today and the coming days without opening a calendar.
4. Configurable alert: control *when* the alert fires and *how* it looks (presets, backdrop, tint, text and button colors), with warnings when a choice is hard to read.
5. Stay small: a native app that idles at near-zero CPU and a few tens of MB of memory.

## 5. Non-goals (explicitly out of scope for v1)

Everything below is intentionally **not** built in v1:

- Custom reminders that are not calendar events
- Event filters (regex / keyword filters to suppress alerts), beyond the out-of-office keywords
- Global keyboard shortcuts and configurable alert shortcuts
- Saved custom themes beyond the four built-in presets, theme sharing, import/export
- Desktop widgets (Notification Center)
- Apple Reminders integration
- Travel time, "Run Shortcut when joining call", privacy mode
- Menu bar title truncation options
- Per-reminder alert-time and sound overrides
- Windows / Linux / iOS

Some of these are cheap to add later; they're excluded to ship a small, solid v1.

## 6. Scope

### P0 — must ship

| # | Feature | What the user gets |
|---|---------|-------------------|
| 1 | **Calendar source** | Events from Google Calendar (see Decision 1 for how). A Calendars settings pane lists every calendar grouped by account, each with a checkbox in the calendar's color, a Select All / Deselect All link per account, a count of selected calendars, a warning when none are selected, when calendars were last updated, and Open Internet Accounts and Refresh Calendars buttons. All-day events, cancelled events and events the user has declined are ignored. |
| 2 | **Full-screen alert** | N minutes before a meeting starts, a borderless window covers every connected display, the main one only, or the one with the pointer (per setting), above every other app including full-screen apps. Centered, top to bottom: the calendar's name and color, a live countdown that changes color as the start passes ("Starts in 2:59", "Starting now", "Started 3 min ago"), the title, the time and location, a **Join** button (when a link is found, `↩`), a snooze row (two durations and **At \<start time\>**), and **Dismiss** (`esc`). Optional auto-close after X minutes. |
| 3 | **Menu bar** | A status item that changes with your day: a countdown to the next meeting later today ("Next in 11 h 40 min", "Next in 42 min" within the hour) or its day and time ("Tomorrow at 1:00 PM", "In 3 days at 9:10 AM"), an accent-colored pill when a meeting is about to start (5 minutes before by default; the timing and colors are set under Appearance), a draining ring and "40 min left" during a meeting, and a crossed-out bell when paused. One setting picks icon only, the time until the next event, or its title and the time until it ("Lunch with Lucía · in 11 h 40 min"). Clicking opens a panel with today's date, one hero card (starting soon, now, next later today, or "No more meetings today"), then Now, Today (every meeting today that hasn't started, the hero's included) and one section per following day. Each row has its time, calendar color, title, and a Join or Directions button. A bell menu pauses reminders; a gear menu opens Settings or quits. |
| 4 | **Settings window** | A standard macOS settings window with a toolbar: **General** (open at login; what the menu bar shows (icon only, time, or title and time); alert lead time from presets or a custom number of minutes; which screens show the alert; sound and repeat; out-of-office events; two snooze durations from presets or a custom number of minutes; auto-close), **Calendars** (see #1), **Appearance** (see #5). The window fits each pane's height. |
| 5 | **Alert appearance** | Four presets (Dark, Light, High contrast, Midnight), then: backdrop (dark or light blur), optional tint color and strength, text color, and the Join and Dismiss & Snooze buttons' text color, fill and fill opacity. Every color can stay **Automatic**, which picks whatever reads best on the backdrop. A warning appears when text or a button label falls below 4.5:1 contrast. A live preview over a sample wallpaper, light app or dark app updates as values change, plus a **Show Demo Alert** button that fires a real alert with a fake event. The same pane sets the menu bar's starting-soon pill: how long before a meeting it appears (5 minutes by default; the panel's starting-soon card follows) and its fill and text colors, with a preview. Restore Defaults. Settings saved by earlier builds carry over. |

### P1 — should ship in v1 if cheap (they are)

| # | Feature | What the user gets |
|---|---------|-------------------|
| 6 | **One-click join** | The app scans the event's location, URL and notes for a video-call link (Google Meet, Zoom, Microsoft Teams, Webex; easy to extend) and surfaces a **Join** button in the alert and the menu bar panel. Opens in the default browser. Meetings with a physical address and no link get a **Directions** button in the panel instead, which opens Apple Maps. |
| 7 | **Alert sound** | Optional system sound when the alert appears, with a "repeat until the alert is closed" toggle. Off by default. |
| 8 | **Out-of-office events** | Events titled like out-of-office blocks ("Out of office", "Fuera de la oficina", "OOO", …) don't alert unless "Alert for out-of-office events" is turned on. They show in the menu bar panel, striped and muted, unless "Show out-of-office events in the list" is turned off. The keywords are editable as tokens in Settings › General. |
| 9 | **Pause reminders** | From the panel's bell menu: pause for 1 hour, until tomorrow, or until resumed. While paused the menu bar shows a crossed-out bell and the panel says until when, with a Resume button. A pause survives quitting and relaunching. |

### P2 — later, if wanted

Direct Google Calendar API integration (see Decision 1), saved custom themes, custom reminders, event filters, Apple Reminders, keyboard shortcuts.

## 7. Key user flows

**First launch**

1. App appears in the menu bar only (no Dock icon).
2. macOS asks for Calendar access. If denied, the menu bar panel explains how to grant it in System Settings.
3. All calendars are on by default. The user opens the panel → gear → Settings → Calendars and unticks the noise (holidays, birthdays).
4. Default lead time is 3 minutes. Done.

**Meeting day**

1. In the morning the menu bar reads "10:00 AM". The panel's hero card says "Next · in 1 h 15 min".
2. Within the hour it counts down: "Next in 9 min". With **Menu bar › Title and time until next event** chosen: "Design Sync · in 9 min".
3. At T-5:00 the item turns into an accent pill, and the panel's hero card reads "Starts in 5 min" with a Join button.
4. At T-3:00 the full-screen alert appears with "Starts in 2:59" and a **Join** button.
5. The user presses `↩` or clicks **Join** (opens Meet), or snoozes **1 min** (the alert returns at T-2:00) or **At 10:00 AM** (it returns at the start), or presses `esc` to dismiss.
6. During the meeting the menu bar shows a ring that drains as time passes and "40 min left". The panel's Now card shows a progress bar.

**Tweaking the alert**

1. Settings → Appearance. Pick the **High contrast** preset, or change the backdrop to light blur and add a 20% tint.
2. Set the Join button's fill to a custom color. If its label becomes hard to read, a contrast warning says so.
3. The preview updates live; switch it between Wallpaper, Light app and Dark app. Click **Show Demo Alert** to see the real thing. Close it with `Esc`.

**Taking a break**

1. Open the panel and click the bell → **Pause until tomorrow**.
2. The menu bar shows a crossed-out bell. The panel says "Reminders paused until tomorrow" with **Resume**.
3. No alerts fire until midnight, even if Join! is quit and relaunched. After that, reminders resume on their own.

## 8. Success criteria

- The alert appears within 2 seconds of the scheduled time, including in these cases: Mac woke from sleep 30 seconds earlier; the event was created 1 minute earlier; the user is in a full-screen app on another Space.
- Events created, moved, or cancelled in Google Calendar are reflected in the app within the calendar sync interval (no app restart needed).
- The menu bar item and panel are never more than 30 seconds behind the clock.
- Idle resource use: negligible CPU, well under 50 MB memory.
- A new user gets to a working setup in under a minute with no documentation.

## 9. Decisions

All were settled on 2026-10-05.

| Decision | Choice | Notes |
|---|---|---|
| Calendar source | **EventKit** via the Mac's own accounts | Google accounts are added in System Settings › Internet Accounts. The direct Google Calendar API remains a P2 option behind the same `CalendarService` protocol. |
| Minimum macOS | **14 Sonoma** | Modern EventKit permission API, `@Observable`, `SMAppService`. |
| Distribution | **Unsigned** (ad-hoc signature pinned to the bundle id) | Built locally with `make run`; no Apple Developer membership needed. The calendar permission survives rebuilds. Notarization can be added later. |
| Name | **Join!** | Bundle id `com.poliuk.join`, executable `Join`. |
| Out-of-office settings | **On the General pane** | The settings design put them on Calendars; the author chose General. |

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
