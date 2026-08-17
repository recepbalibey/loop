# Loop: AI Handoff Document

**Last verified:** 2026-08-17
**Verification method:** Full source code inspection, test execution, build verification

This document is the authoritative handoff for AI sessions. Read it before changing
anything. Source code is the final truth; this document describes what was found.

---

## 1. Project Identity

**What:** A standalone macOS menu bar reminders/to-do app.
**Bundle ID:** `com.loop.menubar`
**Status:** Working product in daily use. Not a prototype.
**Architecture:** Menu bar agent app (LSUIElement = true). No Dock icon.

---

## 2. Environment Constraints

This Mac has **Command Line Tools only, not full Xcode** (`xcode-select -p` →
`/Library/Developer/CommandLineTools`).

| Not available | Why | What is used instead |
|---|---|---|
| SwiftData | Macros need Xcode | `@Observable` + hand-rolled JSON |
| XCTest | Framework absent under CLT | swift-testing (`import Testing`, `@Test`, `#expect`) |
| iOS app / simulator | Needs full Xcode | Nothing. A companion iPhone app is impossible here |
| Xcode previews | Needs Xcode | Build and run the real app |

**Swift version:** 6.3.3 (toolchain), swift-tools-version:5.10 (Package.swift)
**Platform:** macOS 14+ (Sonoma), arm64 only

---

## 3. Build & Test Commands

```bash
swift build        # compile check
./run_tests.sh     # the ONLY correct way to run tests (bare `swift test` won't link)
./build_app.sh     # packages Loop.app (ad-hoc signed)
open Loop.app      # relaunch
pkill -f Loop.app; open Loop.app   # restart
```

After relaunching, sanity check headlessly:
```bash
ps aux | grep -c '[L]oop.app/Contents/MacOS/Loop'   # expect exactly 1
ls -t ~/Library/Logs/DiagnosticReports/ | grep -i loop   # expect nothing new
```

**Test status (verified 2026-08-17):** 111 tests passing in 14 suites.

---

## 4. Source Code Architecture

### Entry Point
`Sources/Loop/App.swift` — `@main struct LoopApp: App` with
`@NSApplicationDelegateAdaptor(AppDelegate.self)`

### Module Structure

```
LoopKit (pure logic, no UI dependencies)
├── Models/
│   ├── ReminderItem.swift      Core data model (242 lines)
│   └── ReminderTemplate.swift  Reusable template model (32 lines)
├── Store/
│   ├── TaskStore.swift          @Observable, JSON-backed (186 lines)
│   └── TemplateStore.swift      @Observable, JSON-backed (56 lines)
└── Utilities/
    ├── NaturalLanguageParser.swift  NSDataDetector + vague phrases (130 lines)
    ├── TimeOfDay.swift              24-hour time parsing (48 lines)
    ├── NotificationIdentifier.swift UUID + checkin suffix (30 lines)
    ├── ICSExport.swift              iCalendar export (74 lines)
    └── MarkdownExport.swift         Checklist export (48 lines)

Loop (AppKit shell + SwiftUI views)
├── App.swift                    AppDelegate (604 lines)
├── Store/
│   ├── NotificationScheduler.swift    Reconciliation model (182 lines)
│   ├── NotificationAuthorization.swift Permission tracking (72 lines)
│   ├── NotificationSoundOption.swift   9 macOS sounds (34 lines)
│   ├── HotKeyRecorder.swift            Local key capture (58 lines)
│   ├── LaunchAtLogin.swift             SMAppService wrapper (22 lines)
│   └── Date+Rounding.swift             5-min rounding (15 lines)
└── Views/
    ├── MenuBarContentView.swift   Main popover UI (660 lines)
    ├── TaskRowView.swift          Individual row (294 lines)
    ├── EditTaskView.swift         Edit window (642 lines)
    ├── PreferencesView.swift      Preferences window (243 lines)
    ├── LiquidGlass.swift          Translucent background (80 lines)
    └── AccentColorOption.swift    8-color palette (42 lines)
```

### Architectural Rules

1. **Anything testable belongs in LoopKit.** Pure Foundation, no AppKit/SwiftUI.
2. **No SwiftUI Scene.** All windows managed by AppDelegate via AppKit directly.
3. **`@Observable` + JSON, not SwiftData.** Hand-written Codable inits for migration.
4. **`withObservationTracking`** is the only way to observe `@Observable` from AppKit.
5. **Notification reconciliation:** Full sync on every data change, not incremental diffs.

---

## 5. Data Storage

**Location:** `~/Library/Application Support/Loop/`
- `reminders.json` — all reminders (ISO 8601 dates, pretty-printed)
- `templates.json` — saved templates

**Corruption handling:** Unreadable files are backed up as
`reminders.corrupted-<timestamp>.json`, never silently discarded.

**No networking.** No entitlements. No sandbox. No keychain access.

---

## 6. Loop.app Bundle (existing artifact)

| Property | Value |
|---|---|
| Bundle ID | com.loop.menubar |
| Version | 1.0 |
| Architecture | arm64 (Mach-O thin) |
| Signing | Ad-hoc (no Team ID) |
| LSUIElement | true (no Dock icon) |
| Info.plist | `Packaging/Info.plist` (source), `Loop.app/Contents/Info.plist` (copy) |
| Icon | `Resources/AppIcon.icns` |
| Entitlements | None |
| Notarization | None |

**Note:** The existing `Loop.app` was built on 2026-08-16. It corresponds to the
current source code based on file dates. Rebuild with `./build_app.sh` after any
source changes.

---

## 7. Tests

**Framework:** swift-testing (not XCTest)
**Runner:** `./run_tests.sh` (required — passes explicit framework flags for CLT)
**Target:** `LoopKitTests` (depends on `LoopKit`)

**14 test suites:**
1. CheckInScheduleTests
2. EndToEndWorkflowTests
3. ICSExportTests
4. MarkdownExportTests
5. NaturalLanguageParserTests
6. NotificationEligibilityTests
7. NotificationIdentifierTests
8. ObservationTrackingTests
9. RecurrenceRuleTests
10. ReminderItemSectionTests
11. TaskStoreTests
12. TemplateStoreTests
13. TimeOfDayTests
14. UpcomingCheckInTests

**Coverage:** Models, stores, parser, exports, scheduling logic. No UI tests.

---

## 8. Implemented Features (VERIFIED)

All features below were confirmed from source code:

- [x] Natural language input ("tomorrow at 3pm", "eod", "at home")
- [x] Complete by checkbox or row text
- [x] Persistent Completed section with Clear Completed
- [x] 4-second Undo toast (not for recurring)
- [x] Search across everything
- [x] Sections: Overdue / Today / Tomorrow / This Week / Later / Someday
- [x] Start time + optional end time via duration presets
- [x] 24-hour HH:mm typing with clock menu
- [x] Full-size calendar popover for date
- [x] Recurring: Daily / Weekdays / Weekly
- [x] Check-ins: repeating notifications every 15/30/45/60 min
- [x] Local notifications with Mark Done / Snooze 1 Hour
- [x] Sound picker (9 sounds) with preview
- [x] Test notification button
- [x] Permission state surfaced honestly
- [x] Icon mode with progress ring
- [x] Live-text mode ("Video Shooting · 45m left")
- [x] Red icon while overdue
- [x] Left-click opens panel, right-click opens menu
- [x] Global hotkey (default ⌥⌘L, rebindable)
- [x] Priority tiers (None/Low/Medium/High) with colour-coded flags
- [x] Drag to reorder within section
- [x] Tag and priority quick-filter chips (AND logic)
- [x] Templates: save and apply
- [x] Keyboard: ↓/↑ select, Enter completes, ⌘Z undoes, Esc closes
- [x] Export: Markdown checklist to clipboard, .ics calendar file
- [x] Accent colour picker (8 options)
- [x] Launch at login
- [x] Single-instance enforcement
- [x] Daily progress ring + "X/Y today" in footer
- [x] Hover polish: row lift/shadow, quick actions, springy checkbox
- [x] Liquid glass effect with holographic sheen
- [x] Right-click menu bar icon for Open/Preferences/Quit

---

## 9. Known Gaps (from BACKLOG.md, verified against source)

1. **Delete is instant and permanent.** No undo for deletion. (VERIFIED: `delete()` in
   TaskStore is `items.removeAll` with no undo mechanism)
2. **No undo for recurring completion.** Recurring items advance, not complete.
   (VERIFIED: `toggleCompletion` in TaskStore)
3. **Snooze on check-in moves whole block.** `reschedule` clears `endDate`.
   (VERIFIED: `reschedule` sets `endDate = nil`)
4. **No keyboard route into Edit window.** Mouse required to open editor.
5. **No multi-select / batch actions.**
6. **No Someday triage flow.**
7. **No import.** Export only.
8. **No day-timeline view.**
9. **No weekly review / history.** Stats are live-only.
10. **Cross-device sync impossible** (needs iOS app + Xcode).

---

## 10. Hard-Won Rules (from BACKLOG.md)

These are fixed, reproduced bugs. Reintroducing the old approach reintroduces the bug.
Each was confirmed in the source code comments:

1. Never set `popover.contentSize` on a shown NSPopover.
2. Never size an NSWindow from `hosting.view.fittingSize`.
3. `EditTaskView` uses a laid-out button bar, not a window toolbar.
4. Use plain `VStack`, not `LazyVStack`, for the reminder list.
5. Prefer unconditional views toggled by opacity over `if`/`if let`.
6. Never use a `.field`-style DatePicker with component steppers.
7. A date-only DatePicker bound to a full Date resets time to noon.
8. Scope `.font()` precisely.
9. `.glassEffect()` renders opaque inside a manually hosted NSPopover.
10. Click targets need `.contentShape(Rectangle())` and padding.
11. `withObservationTracking` is the only way to observe `@Observable` from AppKit.
12. `NSStatusItem` must be `.variableLength`.
13. Status item button only reports left clicks unless `sendAction(on:)` is called.
14. `onChange` fires on the next view update, not at mutation time.
15. Never read `@State` that a text field only writes on focus loss.
16. Edit window needs a fresh SwiftUI identity per presentation.
17. Notification scheduling must not key off "starts in the future".
18. Check-in notification ids are `<uuid>-checkin-<n>`, not bare UUIDs.
19. Tests must not depend on the day they run. Inject `now`.

---

## 11. User Expectations

**Design bar:** "Minimalist, liquid glass design but also interesting, cool, effective,
interactive." Themes: interactivity, effectiveness, liveliness, hologramatic, hovering.
Polish is not optional.

**Writing style:** No em dashes anywhere in user-visible text. Use periods, commas, or
`·`. Code comments were left alone.

**Product constraints:**
- No Apple Reminders / EventKit. Loop owns its own data.
- 24-hour time. No AM/PM in input controls.
- Everything stays local.

**How to work:**
- After a meaningful UI change, ask for a screenshot before moving on.
- Do not guess at causes. Instrument, reproduce, verify.
- Offer options, let the user choose.
- Be honest about limits. State what was verified and what could not be.
- Never touch their data casually. Back up real JSON files.

---

## 12. Security Review

**Performed:** 2026-08-17

| Check | Result |
|---|---|
| API keys / secrets in source | None found |
| Hardcoded credentials | None |
| Networking code | None |
| Entitlements | None |
| Sandbox | Not configured |
| Keychain access | None |
| Shell command execution | None (scripts are build-only, not embedded in app) |
| Hardcoded endpoints | None |
| Private keys / certificates | None in repository |

**Files that should NOT be committed to GitHub:**
- `Loop.app/` — build artifact, rebuilt from source
- `.build/` — SwiftPM build directory
- Any `*.corrupted-*.json` files in Application Support (runtime data)

**No secrets, credentials, or sensitive data were found in the repository.**

---

## 13. .gitignore Decisions

**Created:** `.gitignore` covering:
- `.DS_Store`, macOS metadata
- `.build/`, `.swiftpm/`, `Package.resolved`
- `Loop.app` (rebuilt from source)
- Xcode user data (if ever opened in Xcode)
- Signing credentials (*.p12, *.cer, *.key)
- Temporary files, logs

**Should be committed:**
- `Sources/` — all source code
- `Tests/` — test suite
- `Resources/AppIcon.icns` — app icon
- `Packaging/Info.plist` — bundle configuration
- `Package.swift` — build manifest
- `build_app.sh`, `run_tests.sh` — build/test scripts
- `BACKLOG.md`, `README.md`, `HANDOFF.md` — documentation

**Recommendation on Loop.app:** Do NOT commit. It is a build artifact rebuilt from
source via `./build_app.sh`. The `.gitignore` excludes it.

---

## 14. Current Active Task

No active task could be reliably determined from the repository.

**Suggested first move (from BACKLOG.md):** Delete-undo (#1 gap). It is the only
remaining gap where a single misclick permanently loses data. Mirror the existing
completion-undo pattern in `MenuBarContentView`.

---

## 15. When Starting a New AI Session

1. Read `HANDOFF.md` (this file).
2. Read `README.md`.
3. Read `BACKLOG.md`.
4. Inspect the relevant source files.
5. Verify the handoff against the actual repository.
6. Treat source code as the source of truth.
7. Treat README and backlog as documentation/context.
8. Identify conflicts between documentation and implementation.
9. Understand the current task before changing code.
10. Make the smallest reasonable change needed for the task.

## When Ending an AI Session

1. Finish the current task or clearly identify what remains.
2. Inspect the actual project.
3. Update `HANDOFF.md`.
4. Remove obsolete information.
5. Record completed work.
6. Record remaining work.
7. Record important technical decisions.
8. Record known issues.
9. Record important security considerations.
10. Update the date.

`HANDOFF.md` is a living CURRENT STATE document, not a chronological diary.

Maintain one authoritative `HANDOFF.md`. Do not create:
- `HANDOFF_2.md`
- `HANDOFF_FINAL.md`
- `HANDOFF_NEW.md`

---

## 16. Trust Model

### VERIFIED
Directly confirmed from source code, configuration, tests, or successful execution.

### INFERRED
Reasonably inferred but not explicitly confirmed.

### PLANNED
Documented as future work but not implemented.

### UNKNOWN
Cannot be determined reliably.

### REQUIRES VERIFICATION
Needs runtime testing, another environment, or additional investigation.

Never present inferred, planned, or unknown information as verified.

---

## 17. Do Not Break

- Preserve existing architecture unless explicitly asked to change it.
- Prefer minimal changes.
- Do not rewrite unrelated code.
- Do not remove working functionality.
- Do not remove resources without understanding their use.
- Do not change dependencies unnecessarily.
- Do not change Swift version unnecessarily.
- Do not modify signing/entitlements without explicit approval.
- Do not commit secrets.
- Do not commit private certificates or keys.
- Inspect existing implementation before creating duplicate functionality.
- Run relevant tests after changes.
- Update `HANDOFF.md` when finishing significant work.
- Keep README documentation aligned with actual functionality.

---

## 18. Git/GitHub Status

- **Git initialized:** No
- **`git init` run:** No
- **Commits created:** No
- **Remote configured:** No
- **Anything pushed:** No

The project is prepared for GitHub hosting (`.gitignore`, `README.md`, `HANDOFF.md`
created/updated) but no Git operations were performed.
