# Loop

A minimalist macOS menu bar reminders app. No Dock icon, no Apple Reminders or EventKit
dependency, no network access. Everything lives in local JSON files on your Mac.

> Working on this project? Read **[BACKLOG.md](BACKLOG.md)** first. It covers the build
> environment, current state, remaining gaps, and the design rules that must not be
> undone. Read **[HANDOFF.md](HANDOFF.md)** for the current implementation status and
> architecture details.

## Features

**Capture**
- Click the menu bar icon or press ⌥⌘L (rebindable) to open the panel.
- Type a sentence and press Return. Natural language becomes a due date and an optional
  tag: `tomorrow`, `next friday`, `in 3 days`, `before end of day`, `eod`, `tonight`,
  `end of week`, plus a trailing `at <place>`.
- Save any reminder as a reusable template, then add from it in one click.

**Organise**
- Grouped into Overdue / Today / Tomorrow / This Week / Later / Someday.
- Priority tiers (Low / Medium / High) with colour-coded flags, used as the primary
  sort within a section.
- Drag to reorder within a section.
- Filter by tag or priority from the chip row.
- Search everything, completed items included.

**Schedule**
- A start time, and optionally an end time via duration presets (15m / 30m / 1h / 2h /
  Custom).
- 24-hour `HH:mm` entry with a quick-pick menu of times around now, and a full-size
  calendar for the date.
- Repeat daily, on weekdays, or weekly. Completing a repeating reminder rolls it
  forward instead of filing it away.

**Stay on it**
- Real macOS notifications with **Mark Done** and **Snooze 1 Hour** on the banner.
- Optional check-ins: a repeating "Still on it?" nudge every 15 / 30 / 45 / 60 minutes
  across a scheduled block.
- Choose the alert sound, with a preview button.
- If macOS is blocking notifications, Loop says so and links straight to the setting
  rather than failing silently.

**At a glance**
- The menu bar icon draws a progress ring while a block is running, or switches to live
  text ("Video Shooting · 45m left"). It turns red while anything is overdue.
- A daily progress ring and "X/Y today" in the footer.

**Handle**
- Complete by clicking the checkbox or the row text. A 4-second Undo bar follows.
- Completed items stay in a collapsible section until you clear them.
- Hover a row for quick actions, right-click for the full menu.
- Keyboard: ↓/↑ to select, Return to complete, ⌘Z to undo, Esc to close.
- Right-click the menu bar icon for Open / Preferences / Quit.

**Own your data**
- Everything is in `~/Library/Application Support/Loop/` as plain JSON.
- Copy all reminders as a Markdown checklist, or export scheduled ones as a `.ics`
  calendar file (repeats included) for Calendar or any other calendar app.
- A corrupt data file is backed up, never discarded.

**Make it yours**
- Accent colour picker, icon or live-text menu bar style, custom global shortcut,
  launch at login.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.10+ (swift-tools-version:5.10)
- Command Line Tools or full Xcode

## Building

This project is set up for a machine with **Command Line Tools only**, so it uses
SwiftPM and swift-testing rather than Xcode and XCTest.

```bash
swift build        # compile check
./run_tests.sh     # run the test suite (do not use `swift test` directly)
./build_app.sh     # package Loop.app (ad-hoc signed)
open Loop.app
```

`run_tests.sh` exists because swift-testing needs explicit framework flags to link under
Command Line Tools. 111 tests across 14 suites.

## Architecture

```
Loop/
├── Package.swift              SwiftPM manifest (3 targets)
├── Sources/
│   ├── LoopKit/               Pure, testable logic (no AppKit/SwiftUI)
│   │   ├── Models/            ReminderItem, ReminderTemplate
│   │   ├── Store/             TaskStore, TemplateStore
│   │   └── Utilities/         NaturalLanguageParser, TimeOfDay,
│   │                          NotificationIdentifier, ICSExport, MarkdownExport
│   └── Loop/                  The app (AppKit shell + SwiftUI views)
│       ├── App.swift          AppDelegate: status item, popover, windows, hotkey,
│       │                      notification delegate, .ics export
│       ├── Store/             NotificationScheduler, NotificationAuthorization,
│       │                      NotificationSoundOption, HotKeyRecorder,
│       │                      LaunchAtLogin, Date+Rounding
│       └── Views/             MenuBarContentView, TaskRowView, EditTaskView,
│                               PreferencesView, LiquidGlass, AccentColorOption
├── Tests/LoopKitTests/        14 suites, 111 tests
├── Resources/AppIcon.icns     App icon
├── Packaging/Info.plist       Bundle configuration (com.loop.menubar)
├── build_app.sh               Assembles Loop.app from SwiftPM release build
└── run_tests.sh               Required test runner for swift-testing under CLT
```

**Key architectural decisions:**
- All testable logic lives in `LoopKit` (pure Foundation, no UI). The `Loop` target
  contains only AppKit/SwiftUI glue.
- `@Observable` + hand-rolled JSON instead of SwiftData (macros need full Xcode).
- No SwiftUI Scene; all windows managed directly by `AppDelegate` via AppKit.
- Notification scheduling uses a full reconciliation model on every data change.

## Runtime Data

`~/Library/Application Support/Loop/`
- `reminders.json` — all reminders
- `templates.json` — saved templates

Everything is local. Nothing is sent anywhere.

## Known Limitations

- No cross-device sync (would need iOS app + CloudKit, requires full Xcode).
- No import (`.ics` export exists, import does not).
- Deleting a reminder is instant and permanent (no undo for deletion).
- No undo for completing a recurring reminder.
- No multi-select / batch actions.

## Status

The app is finished enough for daily use and is in daily use. Treat it as a working
product, not a prototype. See **[BACKLOG.md](BACKLOG.md)** for ranked remaining gaps.
