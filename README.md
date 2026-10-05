# Join!

A free, open-source macOS menu bar app that makes calendar meetings impossible to miss.

- **Full-screen alert** a few minutes before each meeting, on every display (or just the main one, or the one with the pointer), above everything else. It shows a live countdown, the title, time and location, and buttons to Join, Snooze, snooze until the start, or Dismiss.
- **Menu bar item** that tells you where you are in your day: the time of the next meeting, "in 42 min" within the hour, an accent pill in the last 5 minutes, and a draining ring with "40 min left" during a meeting. Event titles are optional.
- **Menu bar panel** with one card for what matters now (starting soon, in progress, next, or nothing left today), then the rest of today and the coming days. Overlapping meetings are flagged.
- **One-click Join** for Google Meet, Zoom, Microsoft Teams and Webex links found in the event, and **Directions** in Apple Maps for in-person meetings.
- **Pause reminders** for an hour, until tomorrow, or until you resume.
- **Configurable** lead time, snooze durations, auto-close, sound, and the alert's look: four presets, backdrop, tint, text and button colors (automatic by default), with contrast warnings, a live preview and a demo alert.

Works with any calendar your Mac knows about (Google, iCloud, Exchange, Outlook, CalDAV) through macOS Calendar. Native Swift, no dependencies, idles at a few tens of MB.

## Requirements

- macOS 14 Sonoma or later
- To build: Xcode Command Line Tools (`xcode-select --install`). Full Xcode is only needed to run the unit tests.

## Build and run

```sh
make run
```

This builds `build/Join.app` and opens it. The app lives in the menu bar only; there is no Dock icon. To build without launching, `make app`. Opening the app again while it runs opens Settings.

The app is ad-hoc signed, not notarized. Because you built it locally, Gatekeeper won't complain. If you download a build from somewhere else, right-click the app → Open the first time.

The signature is pinned to the bundle identifier, so macOS remembers the calendar permission across rebuilds. If you built Join! before this change, macOS asks once more after updating.

## First launch

1. macOS asks for calendar access. Approve it. If you miss the prompt, grant it in System Settings › Privacy & Security › Calendars.
2. Click the menu bar item → **⋯** → **Settings…** → **Calendars** and untick the calendars you don't want alerts for (holidays, birthdays).
3. The default alert fires 3 minutes before each meeting. Change it under **General** › **Alert me**.

### Google Calendar

Join! reads calendars through macOS, so your Google account needs to be added in **System Settings › Internet Accounts** with *Calendars* enabled. How quickly changes from Google reach your Mac is controlled in **Calendar › Settings › Accounts › Refresh Calendars**; set it to *Every minute* or *Every 5 minutes* for best results.

## What gets alerted

Every event in the enabled calendars, except all-day events, cancelled events, events you declined, and out-of-office events. Tentative invitations do alert. Out-of-office events are recognised by title ("Out of office", "Fuera de la oficina", "OOO", …). They show striped in the menu bar panel but don't alert; turn on **Settings › General › Out of office › Alert for out-of-office events** to be alerted for them too, or edit the keywords there.

On the alert, **Return** joins the call and **Esc** dismisses. Keys are ignored for the first moment after the alert appears, so a keystroke you were already typing elsewhere can't dismiss it by accident.

If a meeting starts while an alert is due (the Mac was asleep, the app was launched late), the alert fires immediately, unless the meeting started more than 5 minutes ago.

To take a break, click the bell in the menu bar panel and pick **Pause for 1 hour**, **Pause until tomorrow** or **Pause until I resume**. The menu bar shows a crossed-out bell while paused, and the pause survives a relaunch.

## Development

```sh
swift build          # debug build (Command Line Tools are enough)
swift test           # unit tests (needs Xcode for XCTest)
scripts/build-app.sh # assemble build/Join.app
```

The package has two targets:

- `JoinCore` — pure logic with no UI or EventKit dependency: scheduling, link detection, time formatting, preferences, what the menu bar item and panel say, the alert's countdown, colors and contrast. This is what the tests cover.
- `Join` — the app: EventKit calendar service, alert windows, menu bar item and panel, and Settings.

To check the UI against a known calendar instead of your own, quit Join! and launch it with a fixture scenario (`nothing`, `later`, `busy`, `meeting` or `denied`):

```sh
open --env JOIN_FIXTURE=busy build/Join.app
```

Fixture runs keep their settings in a separate defaults domain and never schedule alerts. The app also listens for a few distributed notifications (`com.poliuk.join.openSettings`, `snapshot`, `togglePanel`, `pause`, `appearance`, …) so scripts can open windows, take snapshots and switch light/dark. See [Testing strategy](docs/TECHNICAL_DESIGN.md#12-testing-strategy) in the technical design.

Design documents live in [`docs/`](docs/).

## License

MIT. See [LICENSE](LICENSE).
