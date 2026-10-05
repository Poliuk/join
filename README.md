# Join!

A free, open-source macOS menu bar app that makes calendar meetings impossible to miss.

- **Full-screen alert** a few minutes before each meeting, on every display, above everything else, with a live countdown, Snooze and Dismiss.
- **Menu bar preview** of what's happening now and what's next.
- **One-click Join** for Google Meet, Zoom, Microsoft Teams and Webex links found in the event.
- **Configurable** lead time, snooze durations, sound, and the alert's colors, blur and opacity, with a live preview and a demo alert.

Works with any calendar your Mac knows about (Google, iCloud, Exchange, Outlook, CalDAV) through macOS Calendar. Native Swift, no dependencies, idles at a few tens of MB.

## Requirements

- macOS 14 Sonoma or later
- To build: Xcode Command Line Tools (`xcode-select --install`). Full Xcode is only needed to run the unit tests.

## Build and run

```sh
make run
```

This builds `build/Join.app` and opens it. The app lives in the menu bar only; there is no Dock icon. To build without launching, `make app`.

The app is ad-hoc signed, not notarized. Because you built it locally, Gatekeeper won't complain. If you download a build from somewhere else, right-click the app → Open the first time.

The signature is pinned to the bundle identifier, so macOS remembers the calendar permission across rebuilds. If you built Join! before this change, macOS asks once more after updating.

## First launch

1. macOS asks for calendar access. Approve it. If you miss the prompt, grant it in System Settings › Privacy & Security › Calendars.
2. Open the menu bar icon → gear → **Calendars** and untick the calendars you don't want alerts for (holidays, birthdays).
3. The default alert fires 3 minutes before each meeting. Change it under **General**.

### Google Calendar

Join! reads calendars through macOS, so your Google account needs to be added in **System Settings › Internet Accounts** with *Calendars* enabled. How quickly changes from Google reach your Mac is controlled in **Calendar › Settings › Accounts › Refresh Calendars**; set it to *Every minute* or *Every 5 minutes* for best results.

## What gets alerted

Every event in the enabled calendars, except all-day events, cancelled events, events you declined, and out-of-office events. Tentative invitations do alert. Out-of-office events are recognised by title ("Out of office", "Fuera de la oficina", "OOO", …); turn on **Settings › General › Alert for out-of-office events** to be alerted for them too, or edit the keyword list there.

On the alert, **Esc** dismisses and **Return** joins the call. Keys are ignored for the first moment after the alert appears, so a keystroke you were already typing elsewhere can't dismiss it by accident.

If a meeting starts while an alert is due (the Mac was asleep, the app was launched late), the alert fires immediately, unless the meeting started more than 5 minutes ago.

## Development

```sh
swift build          # debug build (Command Line Tools are enough)
swift test           # unit tests (needs Xcode for XCTest)
scripts/build-app.sh # assemble build/Join.app
```

The package has two targets:

- `JoinCore` — pure logic with no UI or EventKit dependency: scheduling, link detection, time formatting, preferences. This is what the tests cover.
- `Join` — the app: EventKit calendar service, alert windows, menu bar panel and Settings.

Design documents live in [`docs/`](docs/).

## License

MIT. See [LICENSE](LICENSE).
