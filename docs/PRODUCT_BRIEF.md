# Product Brief — Join!

*Status: approved 2026-10-05, updated after the redesign, for in-app updates and for 1.2.0 (2026-10-07) · Open-source (MIT) macOS menu bar app*

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
4. Configurable full-screen alert: control *when* it appears, or turn it off, and *how* it looks (presets, backdrop, tint, text and button colors), with warnings when a choice is hard to read.
5. Stay small: a native app that idles at near-zero CPU and a few tens of MB of memory.

## 5. Non-goals (explicitly out of scope for v1)

Everything below is intentionally **not** built in v1:

- Custom reminders that are not calendar events
- Event filters (regex / keyword filters to suppress alerts), beyond the out-of-office keywords and the choices for out-of-office events and events with no participants
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
| 1 | **Calendar source** | Events from Google Calendar (see Decision 1 for how). A Calendars settings pane lists every calendar grouped by account, each with a checkbox in the calendar's color, a Select All / Deselect All link per account, a count of selected calendars, a warning when none are selected, when calendars were last updated, and Open Internet Accounts and Refresh Calendars buttons. All-day events, cancelled events and events the user has declined are ignored. **Events with no participants**, the ones nobody else is invited to, like focus time or reminders the user adds for themselves, get a choice in Settings › General › Events, next to the one for out-of-office events (#8): **Show and alert** (the default), **Show in the list only** (in the panel's lists, never alerting, never in the menu bar item or the panel's top card) or **Exclude** (left out of the panel, the menu bar and full-screen alerts, as if their calendar were unticked). An event of both kinds gets the choice that shows less. |
| 2 | **Full-screen alert** | N minutes before a meeting starts (or never, with **Alert me** set to **Never**), a borderless window covers every connected display, the main one only (the one with the menu bar), the secondary ones only (every other display, or the main one when it's the only display), or the one with the pointer (per setting, **Show on**), above every other app including full-screen apps. Centered, top to bottom: the calendar's name and color, a live countdown that changes color as the start passes ("Starts in 2:59", "Starting now", "Started 3 min ago"), the title, the time and location, a **Join** button (when a link is found, `↩`), a snooze row (two durations and **At \<start time\>**), and **Dismiss** (`esc`). Optional auto-close after X minutes. |
| 3 | **Menu bar** | A status item that changes with your day: a countdown to the next meeting later today ("Next in 11 h 40 min", "Next in 42 min" within the hour) or its day and time ("Tomorrow at 1:00 PM", "In 3 days at 9:10 AM"), an accent-colored pill when a meeting is about to start (5 minutes before by default; the timing and colors are set under Appearance), a draining ring and "40 min left" during a meeting, and a crossed-out bell when paused. One setting picks icon only, the time until the next event, or its title and the time until it ("Lunch with Lucía · in 11 h 40 min"). Clicking opens a panel with today's date, one hero card (starting soon, now, next later today, or "No more meetings today"), then **Now** and **Upcoming events**: every meeting that hasn't started, the hero's included, with a heading per day (Today, Tomorrow, Wednesday…) in the 7 Days view. A small **Today | 7 Days** switch under the card limits the list to today (7 Days by default, remembered); when nothing is left today, Today is dimmed and the week shows. The panel is frosted glass (Liquid Glass on macOS 26 and later), so its text stays readable over any wallpaper or window. Each row has its time, calendar color, title, and a Join or Directions button. A bell menu pauses full-screen alerts; a gear menu opens Settings or quits. When a new version is out, a bar above the card offers to install it (#10). The menu bar and the card follow the meetings you're attending: a Maybe or unanswered event in progress gives way to an accepted one inside it. |
| 4 | **Settings window** | A standard macOS settings window with a toolbar: **General** (open at login; what the menu bar shows (icon only, time, or title and time); the full-screen alert: when it appears, from presets, a custom number of minutes or Never, which screens show it (all, the main one, the secondary ones or the pointer's, see #2), sound and repeat; one Events section with a choice for events with no participants and one for out-of-office events, and the out-of-office keywords, see #1 and #8; two snooze durations from presets or a custom number of minutes; auto-close; update checks, see #10), **Calendars** (see #1), **Appearance** (see #5). An option that depends on another, like repeat on the sound or a custom number of minutes on Custom, only shows while that one is on. The window fits each pane's height, and switching panes is instant. |
| 5 | **Full-screen alert appearance** | Four presets (Dark, Light, High contrast, Midnight), then: backdrop (dark or light blur), optional tint color and strength, text color, and the Join and Dismiss & Snooze buttons' text color, fill and fill opacity. Every color can stay **Automatic**, which picks whatever reads best on the backdrop. A warning appears when text or a button label falls below 4.5:1 contrast. A live preview over a sample wallpaper, light app or dark app updates as values change, plus a **Show Demo** button that shows a real full-screen alert with a fake event. The same pane sets the menu bar's starting-soon pill: how long before a meeting it appears (5 minutes by default; the panel's starting-soon card follows) and its fill and text colors, with a preview. Restore Defaults. Settings saved by earlier builds carry over. |

### P1 — should ship in v1 if cheap (they are)

| # | Feature | What the user gets |
|---|---------|-------------------|
| 6 | **One-click join** | The app scans the event's location, URL and notes for a video-call link (Google Meet, Zoom, Microsoft Teams, Webex; easy to extend) and surfaces a **Join** button in the alert and the menu bar panel. Opens in the default browser. Meetings with a physical address and no link get a **Directions** button in the panel instead, which opens Apple Maps. |
| 7 | **Full-screen alert sound** | Optional system sound when the full-screen alert appears, with a **Repeat until it's closed** toggle, shown once a sound is picked. Off by default. |
| 8 | **Out-of-office events** | Events titled like out-of-office blocks ("Out of office", "Fuera de la oficina", "OOO", …) get the same choice as events with no participants (#1), **Out-of-office events** in Settings › General › Events. By default it's **Show in the list only**: they show in the menu bar panel's lists, striped and muted, and don't alert. **Show and alert** treats them like any other event, still striped in the lists; **Exclude** leaves them out everywhere. The keywords are editable as tokens in the same section, under **Out-of-office keywords**. |
| 9 | **Pause full-screen alerts** | From the panel's bell menu: pause for 1 hour, until tomorrow, or until resumed. While paused the menu bar shows a crossed-out bell and the panel says until when ("Full-screen alerts paused until 11:50 AM"), with a Resume button. A pause survives quitting and relaunching. |

### Added after v1

| # | Feature | What the user gets |
|---|---------|-------------------|
| 10 | **Updates** (1.1.0) | About once a day Join! asks GitHub for the latest release (an hour later if a check fails). When it's newer, the menu bar panel shows "Join! 1.2.0 is available" with **Install**, which downloads it, checks it, replaces the app and relaunches; no Open Anyway step. An offer survives a relaunch: Join! checks again at launch and offers it if it's still the latest. If it can't replace itself, it puts the new version in Downloads, shows it in Finder and says "Quit Join!, then move Join! 1.2.0 to Applications". A release that needs a newer macOS than the Mac has is still offered, since GitHub doesn't say which macOS a release needs; once Install finds out, Settings says "Join! 2.0.0 needs macOS 15.0 or later" and that release isn't offered again. A failed check stays quiet: only Settings says "Couldn't check for updates". Settings › General › Updates shows the version and when it last checked, with **Check Now** and a switch for the daily check (on by default). The request sends only the app's version and a fixed English language header; GitHub also sees the Mac's IP address. |

### P2 — later, if wanted

Direct Google Calendar API integration (see Decision 1), saved custom themes, custom reminders, event filters, Apple Reminders, keyboard shortcuts.

## 7. Key user flows

**First launch**

1. App appears in the menu bar only (no Dock icon).
2. macOS asks for Calendar access. If denied, the menu bar panel explains how to grant it in System Settings.
3. All calendars are on by default. The user opens the panel → gear → Settings → Calendars and unticks the noise (holidays, birthdays). To drop focus blocks and other events nobody else is invited to, they set **Events with no participants** to **Exclude** on the General pane.
4. Default lead time is 3 minutes. Done.

**Meeting day**

1. In the morning the menu bar reads "10:00 AM". The panel's hero card says "Next · in 1 h 15 min".
2. Within the hour it counts down: "Next in 9 min". With **Menu bar › Title and time until next event** chosen: "Design Sync · in 9 min".
3. At T-5:00 the item turns into an accent pill, and the panel's hero card reads "Starts in 5 min" with a Join button.
4. At T-3:00 the full-screen alert appears with "Starts in 2:59" and a **Join** button.
5. The user presses `↩` or clicks **Join** (opens Meet), or snoozes **1 min** (the alert returns at T-2:00) or **At 10:00 AM** (it returns at the start), or presses `esc` to dismiss.
6. During the meeting the menu bar shows a ring that drains as time passes and "40 min left". The panel's Now card shows a progress bar.

**Tweaking the full-screen alert**

1. Settings → Appearance. Pick the **High contrast** preset, or change the backdrop to light blur and add a 20% tint.
2. Set the Join button's fill to a custom color. If its label becomes hard to read, a contrast warning says so.
3. The preview updates live; switch it between Wallpaper, Light app and Dark app. Click **Show Demo** to see the real thing. Close it with `Esc`.

**Updating**

1. A new version is published. Within a day the panel shows "Join! 1.2.0 is available" with **Install**.
2. The user clicks **Install**. The bar reads "Downloading Join! 1.2.0… 45%", then "Installing Join! 1.2.0…", and Join! relaunches as the new version.
3. If Join! can't replace itself, the bar reads "Quit Join!, then move Join! 1.2.0 to Applications" and **Show in Finder** shows the new copy.

**Taking a break**

1. Open the panel and click the bell → **Pause until tomorrow**.
2. The menu bar shows a crossed-out bell. The panel says "Full-screen alerts paused until tomorrow" with **Resume**.
3. No full-screen alerts appear until midnight, even if Join! is quit and relaunched. After that, they resume on their own.
4. To do without them for good, the user sets **Alert me** to **Never** in Settings › General › Full-screen alert. The menu bar item and the panel keep counting down; picking a time again brings the alerts back.

## 8. Success criteria

- The alert appears within 2 seconds of the scheduled time, including in these cases: Mac woke from sleep 30 seconds earlier; the event was created 1 minute earlier; the user is in a full-screen app on another Space.
- Events created, moved, or cancelled in Google Calendar are reflected in the app within the calendar sync interval (no app restart needed).
- The menu bar item and panel are never more than 30 seconds behind the clock.
- Idle resource use: negligible CPU, well under 50 MB memory.
- A new user gets to a working setup in under a minute with no documentation.

## 9. Decisions

All were settled on 2026-10-05, except where a row gives a later date.

| Decision | Choice | Notes |
|---|---|---|
| Calendar source | **EventKit** via the Mac's own accounts | Google accounts are added in System Settings › Internet Accounts. The direct Google Calendar API remains a P2 option behind the same `CalendarService` protocol. |
| Minimum macOS | **14 Sonoma** | Modern EventKit permission API, `@Observable`, `SMAppService`. |
| Distribution | **Unsigned** (ad-hoc signature pinned to the bundle id) | Downloaded from GitHub Releases (`Join.zip`, a universal app) or built locally with `make run`; no Apple Developer membership needed. The calendar permission survives rebuilds and updates. Notarization can be added later. |
| Releases | **Tag-based** (2026-10-06) | Commits to main only run CI; pushing a `vX.Y.Z` tag on main publishes a release. Semantic versioning, starting at 1.0.0. See [RELEASING.md](RELEASING.md). |
| Name | **Join!** | Bundle id `com.poliuk.join`, executable `Join`. |
| App icon | **Amber tile, countdown ring, camera** | A white ring with three quarters of the time left around a dark video camera, on an amber tile. Picked from four variations on a countdown ring (2026-10-06). |
| Out-of-office settings | **On the General pane** | The settings design put them on Calendars; the author chose General. Since 1.2.0 they're part of its Events section. |
| Events with no participants | **Shown by default, and can be left out everywhere** (2026-10-07) | The user asked for a way to leave out events nobody else is on, shown by default. A participant is anyone on the event other than the user: an attendee who isn't them, or an organizer who isn't them. Leaving them out works like an unchecked calendar but decided per event: the panel's card and lists, the menu bar item and alerts. 1.1.0 shipped it as a switch, "Show events with no participants", under the calendar list; 1.1.1 moved the switch to its own Events section on the General pane at the user's request; 1.2.0 turns it into a choice (Events section, below). |
| Updates | **In-app, from GitHub Releases** (2026-10-07) | A daily check of the latest release on GitHub, on by default, with a switch in Settings › General › Updates. **Install** downloads `Join.zip` inside the app, so it isn't quarantined and needs no Open Anyway; it checks GitHub's SHA-256 digest, the bundle id, the version, the processor architecture, the minimum macOS and the signature, then swaps the app and relaunches, or reveals the new copy in Finder when it can't. No Sparkle, no silent installs. The gear menu stays Settings and Quit. Ships in 1.1.0; copies of 1.0.0 are updated by hand once. |
| Dependent settings | **Hidden while their parent is off** (2026-10-07) | An option that only matters when another is on sits indented under it and only shows while that one is on: **Repeat until it's closed** once a sound is chosen, a custom number of minutes once Custom is picked, tint strength once there's a tint. It's never shown dimmed. The user asked for this for every nested option. Repeat and tint strength keep their values while hidden, so they come back as they were. Ships in 1.1.1. |
| Events section | **One choice per kind of event** (2026-10-07) | For 1.2.0 the user merged the Events and Out of office sections into one **Events** section, option B of the design canvas: a pop-up for **Events with no participants** and one for **Out-of-office events**, each offering **Show and alert**, **Show in the list only** and **Exclude**, then **Out-of-office keywords**. The user picked the word Exclude. The defaults keep 1.1's behaviour: Show and alert for events with no participants, Show in the list only for out-of-office events. Show in the list only keeps an event in the panel's lists but never lets it alert, drive the menu bar item or take the panel's card; Exclude leaves it out everywhere. An event of both kinds gets the choice that shows less. 1.1's switches carry over: participants on → Show and alert, off → Exclude; out of office, list and alert on → Show and alert, list on and alert off → Show in the list only, both off → Exclude, and list off with alert on → Show and alert, so those alerts keep working. Ships in 1.2.0. |
| Turning full-screen alerts off | **Never in Alert me** (2026-10-07) | The user asked to let people turn the alerts off by adding **Never** to the **Alert me** pop-up, which now lists When the event starts, 1 minute before, 3 minutes before, 5 minutes before, Never, then Custom…. 2 and 10 minutes left the presets; a stored 2 or 10 shows as Custom. 3 minutes stays the default. With Never no full-screen alert is scheduled or shown, while the menu bar item, its starting-soon pill, the panel and Show Demo keep working, and the section's other settings stay visible (the user's choice). The lead time is kept, and picking a time turns alerts back on at once with that time; Custom… does too, with the kept time in its field (the user found waiting for a saved value broken). An alert already on screen when Never is picked stays until it's closed (the lead's choice, for least surprise). Ships in 1.2.0. |
| Naming | **"Full-screen alert"** (2026-10-07) | The user asked to call the alert "Full-screen alert" everywhere in the app. The noun is renamed and the verb stays, the lead's rule, which the user accepted: **Alert me**, **Show and alert** and "alert you" keep "alert". The section on General and Appearance is **Full-screen alert**; **Show alert on** became **Show on**, **Repeat until the alert is closed** became **Repeat until it's closed**, **Close alerts automatically** became **Close full-screen alerts automatically**, and **Show Demo Alert** became **Show Demo**. The bell's **Pause reminders** and **Resume reminders** became **Pause full-screen alerts** and **Resume full-screen alerts**, and the paused bar reads "Full-screen alerts paused until 11:50 AM". Ships in 1.2.0. |
| Secondary screen only | **A Show on choice for every display but the main one** (2026-10-07) | The user asked for **Secondary screen only** in the full-screen alert's **Show on** pop-up, after **Main screen only** and before **Screen with the pointer**; **All screens** stays first, and the default (the lead's order). The lead's definition: the main screen is the one with the menu bar, what macOS calls the main display, and Secondary screen only covers every other connected display. With only one display connected it falls back to the main one, so the alert never silently vanishes. **Main screen only** now means that same screen; before, it took the screen with the key window, which could be a secondary one while Join!'s Settings window sat there. Choices saved by earlier builds keep working. Ships in 1.2.0. |
| Settings tabs | **Switch instantly** (2026-10-07) | The user asked for no animation between the Settings panes: no crossfade and no animated resize when switching. A pane that changes height while it's shown, when a row appears or goes, resizes as before. Ships in 1.2.0. |

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
| M4 | Join-link detection, sound, launch at login, sleep/wake hardening, release builds on GitHub | 1–2 d |

Roughly 1.5 to 2 weeks of part-time work to a shareable v1.
