# Loop: Project Backlog & Handover

Single source of truth for this project. Read it fully before changing anything.

Loop is a standalone macOS menu bar reminders app. It is finished enough to use daily
and is in daily use. Treat it as a working product, not a prototype.

Last verified: all 111 tests passing, clean build, app running.

---

## 1. The environment (read this first, it constrains everything)

This Mac has **Command Line Tools only, not full Xcode** (`xcode-select -p` →
`/Library/Developer/CommandLineTools`). Consequences, all of which have already been
worked around, so do not "fix" them:

| Not available | Why | What is used instead |
|---|---|---|
| SwiftData | Its macros need Xcode | `@Observable` + hand-rolled JSON (`TaskStore`) |
| XCTest | Framework absent under CLT | swift-testing (`import Testing`, `@Test`, `#expect`) |
| iOS app / simulator | Needs full Xcode | Nothing. A companion iPhone app is impossible here |
| Xcode previews | Needs Xcode | Build and run the real app |

**swift-testing needs explicit framework flags to even link.** That is what
`run_tests.sh` is for.

```bash
swift build        # compile check
./run_tests.sh     # the ONLY correct way to run tests here. Never bare `swift test`
./build_app.sh     # packages Loop.app (ad-hoc signed)
pkill -f Loop.app; open Loop.app   # relaunch
```

After relaunching, sanity check headlessly:

```bash
ps aux | grep -c '[L]oop.app/Contents/MacOS/Loop'   # expect exactly 1
ls -t ~/Library/Logs/DiagnosticReports/ | grep -i loop   # expect nothing new
```

### You cannot see the screen

There is no Screen Recording or Accessibility access, by the user's explicit choice.
You cannot click, screenshot, or observe the UI. Verify by:

- unit tests (the data layer is well covered; put logic there so it *can* be tested)
- reading the JSON data files directly
- process and crash-log checks
- temporary instrumentation that writes to a file, then **removed again**
- asking the user for a screenshot

Never claim a UI behaviour works when you have only read the code. Say which parts you
verified and which need the user's eyes. This has caught real bugs that "looked correct".

---

## 2. Layout

```
focusing/
├── focusing.mp4              original design-reference video
└── Loop/
    ├── BACKLOG.md            this file
    ├── README.md             short project readme
    ├── Package.swift         SwiftPM, macOS 14+, swift-tools 5.10
    ├── run_tests.sh          REQUIRED test runner
    ├── build_app.sh          packages Loop.app
    ├── Packaging/            Info.plist (bundle id: com.loop.menubar)
    ├── Resources/
    ├── Loop.app              built bundle
    ├── Sources/
    │   ├── LoopKit/          pure, testable, no AppKit/SwiftUI
    │   │   ├── Models/       ReminderItem, ReminderTemplate
    │   │   ├── Store/        TaskStore, TemplateStore
    │   │   └── Utilities/    NaturalLanguageParser, TimeOfDay,
    │   │                     NotificationIdentifier, ICSExport, MarkdownExport
    │   └── Loop/             the app (AppKit shell + SwiftUI views)
    │       ├── App.swift     AppDelegate: status item, popover, windows, hotkey,
    │       │                 notification delegate, .ics export
    │       ├── Store/        NotificationScheduler, NotificationAuthorization,
    │       │                 NotificationSoundOption, HotKeyRecorder,
    │       │                 LaunchAtLogin, Date+Rounding
    │       └── Views/        MenuBarContentView, TaskRowView, EditTaskView,
    │                         PreferencesView, LiquidGlass, AccentColorOption
    └── Tests/LoopKitTests/   14 suites, 111 tests
```

**Architectural rule:** anything that can be pure logic belongs in `LoopKit` so it can
be unit tested. Several real bugs were only catchable once logic moved there. When you
find yourself unable to test something, that is usually a signal to move it.

### Runtime data

`~/Library/Application Support/Loop/`
- `reminders.json`: the reminders
- `templates.json`: saved templates

Everything is local. Nothing is sent anywhere. A corrupt `reminders.json` is backed up
as `reminders.corrupted-<timestamp>.json` rather than discarded.

---

## 3. What is built and working

**Core**
- Add via natural language ("tomorrow at 3pm", "friday eod", trailing "at <tag>")
- Complete by clicking the checkbox *or* the row's text
- Persistent, collapsible Completed section; Clear Completed with confirmation
- 4-second Undo toast after completing (not offered for recurring, see gaps)
- Search across everything, completed included
- Sections: Overdue / Today / Tomorrow / This Week / Later / Someday

**Scheduling**
- Start time, plus optional end time via duration presets (15m/30m/1h/2h/Custom)
- 24-hour `HH:mm` typing, with a clock menu of quick times built around *now*
- Date via a full-size graphical calendar popover
- Recurring: Daily / Weekdays / Weekly. Completing rolls it forward instead of
  filing it under Completed
- Check-ins: repeating "Still on it?" notifications every 15/30/45/60 min across a block

**Notifications**
- Local notifications with Mark Done / Snooze 1 Hour actions
- Sound picker (9 classic macOS sounds) with a live preview button
- Test notification button
- Permission state surfaced honestly (banner + Preferences row + bell icon truthfulness)

**Menu bar**
- Icon mode, with a progress ring drawn while a block is running
- Live-text mode ("Video Shooting · 45m left" / "AI Sec Prep · in 2h")
- Red icon while anything is overdue; refreshed on data change *and* a 60s timer
- Left-click opens the panel, right-click/control-click opens Open/Preferences/Quit
- Global hotkey, default ⌥⌘L, rebindable in Preferences

**Organisation**
- Priority tiers (None/Low/Medium/High) with colour-coded flags; primary sort key
- Drag to reorder within a section
- Tag and priority quick-filter chips (combine with AND)
- Templates: save a reminder as a reusable template, apply from the footer menu

**Other**
- Keyboard: ↓/↑ select, Enter completes, ⌘Z undoes last completion, Esc closes
- Export: Markdown checklist to clipboard, `.ics` calendar file (with RRULEs)
- Accent colour picker (8 options), launch at login, single-instance enforcement
- Daily progress ring + "X/Y today" in the footer
- Hover polish: row lift/shadow, quick actions, springy checkbox, glass sheen,
  search focus glow

---

## 4. What is missing (ranked)

1. **Deleting a reminder is instant and permanent.** Undo covers completion only. One
   misclick in the context menu loses data. *This is the highest-value fix left.*
2. **No undo for completing a recurring reminder.** It rolls the date forward, so an
   accidental completion means manually editing the date back. Undo is deliberately
   suppressed for these because re-running `toggleCompletion` would advance it *again*
   rather than revert. Reverting needs the previous date stored somewhere.
3. **Snooze on a check-in is surprising.** It moves the whole block's start and clears
   its end date (`reschedule` clears `endDate`), so the remaining check-ins vanish.
4. **No keyboard route into the Edit window.** Arrows/Enter work; opening the editor
   still needs the mouse.
5. **No multi-select / batch actions.**
6. **No Someday triage flow** for the undated pile.
7. **No import.** `.ics` export exists, import does not.
8. **No day-timeline view** (blocks positioned by time of day rather than a list).
9. **No weekly review / history.** Stats are today-only and computed live; nothing is
   stored, so trends are impossible without adding history.
10. **Cross-device sync is impossible here.** It would need an iOS app + CloudKit, and
    the iOS half cannot be built without full Xcode. The user knows and accepts this.

---

## 5. Hard-won rules, do not undo these

Each one is a fixed, reproduced bug. Reintroducing the old approach reintroduces the bug.

1. **Never set `popover.contentSize` on a shown NSPopover.** It jumps across the screen.
   Let it size itself once from the hosting controller; control size via the SwiftUI
   `.frame()`.
2. **Never size an NSWindow from `hosting.view.fittingSize`.** It produced a window too
   narrow for a 3-item toolbar, which silently collapsed the *Save* button behind an
   overflow chevron. Always set an explicit `NSSize` matching the view's own `.frame`.
3. **`EditTaskView` uses a laid-out button bar, not a window toolbar.** Same reason.
4. **Use plain `VStack`, not `LazyVStack`, for the reminder list.** LazyVStack's
   measurement caching left a row showing stale content after an edit.
5. **Prefer unconditional views toggled by opacity over `if`/`if let`** for small row
   content, to avoid conditional-view-identity staleness.
6. **Never use a `.field`-style DatePicker with component steppers.** It is far too easy
   to nudge the month by accident. Use duration presets; `.compact`/`.graphical` only.
7. **A date-only `DatePicker` bound to a full `Date` resets the time to noon.** Route
   every calendar edit through a binding that re-applies the existing time-of-day.
8. **Scope `.font()` precisely.** Chaining it onto a `Section` shrinks every control
   inside it, not just the footer.
9. **`.glassEffect()` renders opaque inside a manually hosted NSPopover.** Use
   `.regularMaterial`.
10. **Click targets need `.contentShape(Rectangle())` and padding.** A stroked circle
    only hit-tests on its visible ring.
11. **`withObservationTracking` is the only way to observe `@Observable` from AppKit.**
    Not Combine, not KVO. It must re-arm itself each time.
12. **`NSStatusItem` must be `.variableLength`.** `.squareLength` crushes live text.
13. **A status item button only reports left clicks** unless you call
    `sendAction(on: [.leftMouseUp, .rightMouseUp])`. Three earlier right-click attempts
    failed purely because of this. Detach a temporarily attached menu in `menuDidClose`,
    never on the line after `performClick`.
14. **`onChange` fires on the *next* view update, not at mutation time.** A `hasLoaded`
    guard inside one did not guard anything, and opening a reminder silently overwrote
    its start time with "now". Use a custom `Binding` when a side effect must happen only
    on real user interaction.
15. **Never read `@State` that a text field only writes on focus loss.** Saving raced
    with the focus change, so the first save stored the *old* time. `EditTaskView.save()`
    derives values synchronously via `resolvedSchedule()`. Keep it that way.
16. **The Edit window needs a fresh SwiftUI identity per presentation.** Keying on the
    reminder id alone preserved `@State` across opens, showing stale values and silently
    reverting reschedules made from the list.
17. **Notification scheduling must not key off "starts in the future".** That is false
    once a block begins, which made every remaining check-in look stale and get
    cancelled mid-block. Use `upcomingCheckIns(now:)`; keep check-in indices stable.
18. **Check-in notification ids are `<uuid>-checkin-<n>`, not bare UUIDs.** Parse them
    with `NotificationIdentifier.reminderID(from:)`, or every action button on a check-in
    silently does nothing.
19. **Tests must not depend on the day they run.** Inject `now`. A test asserting
    "the day after this week is Later" passed all week and failed on a Sunday.

---

## 6. The user's expectations and working rules

**Design bar.** "Minimalist, liquid glass design but also interesting, cool, effective,
interactive." Recurring themes, in their words: *interactivity, effectiveness,
liveliness, hologramatic, hovering*. They explicitly hold it to an "Apple would not ship
this" standard and will say so bluntly. Polish is not optional here; a feature that
works but feels flat will come back.

**Writing style.** **No em dashes anywhere in user-visible text.** This was an explicit
instruction and the whole app was swept for it. Use periods, commas, or `·`. (Code
comments were left alone.) Keep new strings compliant.

**Product constraints.**
- No Apple Reminders / EventKit. Loop owns its own data.
- 24-hour time. No AM/PM in input controls.
- Everything stays local.

**How they want you to work.**
- **Do not go blind.** After a meaningful UI change, ask for a screenshot of that exact
  screen before moving on. Do not batch many unverified visual changes.
- **Do not guess at causes.** They have pushed back hard on speculation. Instrument,
  reproduce, verify, then remove the instrumentation.
- **Offer options, let them choose.** The established rhythm is: propose 3-4 concrete
  features with trade-offs, they pick, you build. They dislike being handed a generic
  list; specificity matters.
- **Be honest about limits.** State plainly what you verified and what you could not.
  They respond well to "this needs your eyes" and badly to overclaiming.
- **Never touch their data casually.** If a verification needs the real JSON file, back
  it up, restore it exactly, and say so.

**Tone they have used when unhappy**, so you can recognise it early: "it is not
functioning app properly, not useful at all", "not how I wanted", "it looks ugly as
well". That is a signal to stop adding and start fixing.

---

## 7. Suggested first moves

1. Read this file, `README.md`, then `ReminderItem.swift` and `TaskStore.swift`.
2. Run `./run_tests.sh` and expect **111 passing in 14 suites**. If not, fix that first.
3. `swift build && ./build_app.sh && open Loop.app`, confirm one process, no crashes.
4. Pick from §4. **Delete-undo (#1) is the recommended first task.** It is the only
   remaining gap where a single misclick permanently loses data.
5. Before building it, offer the user the options and let them choose.

### Delete-undo sketch

Mirror the existing completion-undo. `MenuBarContentView` already has
`recentlyCompletedID` + `undoTask` + `undoBar`. Deletion needs the removed
`ReminderItem` *and* its index kept aside so it can be reinserted in place. Consider
generalising both into one "last reversible action" concept rather than two parallel
mechanisms. That would also open the door to gap #2, since a recurring reminder's
previous date could be captured the same way.
