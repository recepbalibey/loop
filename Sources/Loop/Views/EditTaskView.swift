import SwiftUI
import LoopKit

/// A regular (non-menu-bar) window for the fuller editing surface a small
/// popover can't comfortably hold: notes, an explicit date picker, tag.
struct EditTaskView: View {
    let itemID: ReminderItem.ID
    /// Closes the AppKit window hosting this view. Deliberately not `@Environment(\.dismiss)` —
    /// this view is hosted in a plain NSWindow we manage ourselves, not a SwiftUI-presented
    /// sheet/scene, so the environment dismiss action isn't guaranteed to do anything.
    var onDismiss: () -> Void

    @Environment(TaskStore.self) private var store
    @AppStorage(PreferenceKeys.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(PreferenceKeys.accentColorOption) private var accentColorOptionRaw = AccentColorOption.system.rawValue

    private var accentColor: Color { resolvedAccentColor(from: accentColorOptionRaw) }

    @State private var title = ""
    @State private var notes = ""
    @State private var tag = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Date.now
    @State private var durationPreset: DurationPreset = .none
    @State private var checkInPreset: CheckInPreset = .none
    @State private var repeatRule: RepeatOption = .never
    @State private var hasLoaded = false
    @State private var isDatePickerPresented = false
    @State private var timeText = "00:00"
    @FocusState private var isTimeFieldFocused: Bool
    @State private var isEndDatePickerPresented = false
    @State private var endTimeText = "00:00"
    @FocusState private var isEndTimeFieldFocused: Bool
    @State private var saveGlowOpacity: Double = 0

    private static let dateButtonFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter
    }()


    /// Quick-pick times built around the actual current moment (rounded to the
    /// nearest 15 minutes) rather than fixed day-parts — "what's near now" is more
    /// useful when scheduling something than a static 9/12/15/18/21 list, and it
    /// matches what was asked for directly.
    private static func quickTimes(around now: Date = .now) -> [(label: String, hour: Int, minute: Int)] {
        let calendar = Calendar.current
        let currentMinute = calendar.component(.minute, from: now)
        let roundedMinute = (currentMinute / 15) * 15
        let anchor = calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: roundedMinute,
            second: 0,
            of: now
        ) ?? now

        return [-15, 0, 15, 30, 45].compactMap { offset -> (String, Int, Int)? in
            guard let date = calendar.date(byAdding: .minute, value: offset, to: anchor) else { return nil }
            let hour = calendar.component(.hour, from: date)
            let minute = calendar.component(.minute, from: date)
            return (String(format: "%02d:%02d", hour, minute), hour, minute)
        }
    }

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A dropdown of common durations rather than a free-entry "end date" field.
    /// A raw date picker for the end time turned out to be genuinely dangerous here —
    /// its per-component stepper arrows make it easy to bump the *month* by accident
    /// while trying to nudge the hour, silently producing something like "ends a month
    /// later" with no obvious sign anything went wrong. A duration has no month field
    /// to mis-click in the first place. Custom is still available for the rare case
    /// that actually needs an exact end date.
    private enum DurationPreset: String, CaseIterable, Identifiable {
        case none = "No end time"
        case fifteenMinutes = "15 minutes"
        case thirtyMinutes = "30 minutes"
        case oneHour = "1 hour"
        case twoHours = "2 hours"
        case custom = "Custom…"

        var id: String { rawValue }

        var interval: TimeInterval? {
            switch self {
            case .none, .custom: return nil
            case .fifteenMinutes: return 15 * 60
            case .thirtyMinutes: return 30 * 60
            case .oneHour: return 3600
            case .twoHours: return 2 * 3600
            }
        }

        static func matching(intervalSeconds: TimeInterval) -> DurationPreset {
            for preset in allCases {
                if let target = preset.interval, abs(intervalSeconds - target) < 1 {
                    return preset
                }
            }
            return .custom
        }
    }

    /// How often to send a "still on it?" check-in notification while working through
    /// a scheduled block — for staying focused on what was planned, not just being
    /// told once that it started. Only offered once an end time exists, since a
    /// check-in schedule needs a block to check in *across*.
    private enum CheckInPreset: String, CaseIterable, Identifiable {
        case none = "Off"
        case every15 = "Every 15 min"
        case every30 = "Every 30 min"
        case every45 = "Every 45 min"
        case everyHour = "Every hour"

        var id: String { rawValue }

        var minutes: Int? {
            switch self {
            case .none: return nil
            case .every15: return 15
            case .every30: return 30
            case .every45: return 45
            case .everyHour: return 60
            }
        }

        static func matching(minutes: Int?) -> CheckInPreset {
            guard let minutes else { return .none }
            return allCases.first { $0.minutes == minutes } ?? .none
        }
    }

    /// Thin wrapper around `RecurrenceRule?` so the Picker has a plain, non-optional
    /// `CaseIterable` type to bind to — SwiftUI Pickers don't handle an `Optional` enum
    /// selection cleanly.
    private enum RepeatOption: String, CaseIterable, Identifiable {
        case never = "Never"
        case daily = "Daily"
        case weekdays = "Weekdays"
        case weekly = "Weekly"

        var id: String { rawValue }

        var rule: RecurrenceRule? {
            switch self {
            case .never: return nil
            case .daily: return .daily
            case .weekdays: return .weekdays
            case .weekly: return .weekly
            }
        }

        static func matching(_ rule: RecurrenceRule?) -> RepeatOption {
            guard let rule else { return .never }
            switch rule {
            case .daily: return .daily
            case .weekdays: return .weekdays
            case .weekly: return .weekly
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.system(size: 17, weight: .semibold))
                }

                Section {
                    Toggle("Starts at a specific time", isOn: hasDueDateBinding)
                        .font(.system(size: 14))

                    if hasDueDate {
                        // Date and time are two separate rows rather than one combined
                        // DatePicker. The combined control's compact popover mixed a
                        // graphical calendar with a text-editable time field that had
                        // its own tiny per-component steppers — fiddly to hit precisely
                        // and, per direct feedback, ugly floating over the rows below
                        // it. Splitting them lets the date open a full-size calendar of
                        // our own sizing, and the time use big, no-stepper controls.
                        dateRow
                            .onChange(of: dueDate) { _, newStart in
                                // Single place that reacts to *any* change to dueDate —
                                // from typing, a quick-pick, or the calendar popover —
                                // so the text field and the duration/end-date cascade can
                                // never drift out of sync with each other again.
                                timeText = TimeOfDay(date: newStart).formatted
                                if let interval = durationPreset.interval {
                                    endDate = newStart.addingTimeInterval(interval)
                                } else if durationPreset == .custom, endDate <= newStart {
                                    endDate = newStart.addingTimeInterval(3600)
                                }
                            }

                        timeRow

                        Picker("Duration", selection: $durationPreset) {
                            ForEach(DurationPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .font(.system(size: 14))
                        .onChange(of: durationPreset) { _, newPreset in
                            switch newPreset {
                            case .none:
                                hasEndDate = false
                                checkInPreset = .none
                            case .custom:
                                hasEndDate = true
                                if endDate <= dueDate { endDate = dueDate.addingTimeInterval(3600) }
                                endTimeText = TimeOfDay(date: endDate).formatted
                            default:
                                hasEndDate = true
                                if let interval = newPreset.interval {
                                    endDate = dueDate.addingTimeInterval(interval)
                                }
                            }
                        }

                        if durationPreset == .custom {
                            endDateRow
                                .onChange(of: endDate) { _, newEnd in
                                    endTimeText = TimeOfDay(date: newEnd).formatted
                                }
                            endTimeRow
                        }

                        if hasEndDate {
                            Picker("Check in every", selection: $checkInPreset) {
                                ForEach(CheckInPreset.allCases) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .font(.system(size: 14))
                        }

                        Picker("Repeat", selection: $repeatRule) {
                            ForEach(RepeatOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .font(.system(size: 14))
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    // Scoped to just this Text, not the whole Section — it was
                    // previously chained onto the entire section (toggles, picker,
                    // labels included), making every control in it tiny.
                    Text(scheduleFooterText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .font(.system(size: 14))
                        .frame(minHeight: 48, maxHeight: 64)
                }

                Section("Tag") {
                    TextField("e.g. home, office", text: $tag)
                        .font(.system(size: 14))
                }
            }
            .formStyle(.grouped)
            .controlSize(.large)

            Divider()

            // An explicit button bar instead of a window toolbar: a toolbar with three
            // items collapsed "Save Changes" behind an overflow ">>" chevron whenever
            // the window was even slightly too narrow, leaving no visible save control
            // at all (confirmed via screenshot). A bar we lay out ourselves can never
            // silently hide its own primary button.
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    store.delete(itemID)
                    onDismiss()
                } label: {
                    Text("Delete")
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Spacer()

                Button("Cancel", action: onDismiss)
                    .buttonStyle(.bordered)
                    .help("Discard changes and close this window")

                Button {
                    save()
                } label: {
                    Text("Save Changes")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isTitleEmpty)
                .help("Save and close this window")
                // A slow, faint breathing glow while there's something to save — a
                // quiet "this is the button you want" cue, not an alert.
                .shadow(color: accentColor.opacity(isTitleEmpty ? 0 : saveGlowOpacity), radius: 8)
                .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { saveGlowOpacity = 0.55 } }
            }
            .padding(16)
        }
        .frame(width: 380, height: 480)
        .tint(accentColor)
        .navigationTitle("Edit Reminder")
        .onAppear(perform: loadIfNeeded)
    }

    /// A calendar-only picker rendered in a popover we size ourselves — the system's
    /// default compact-style calendar popover came out noticeably small (direct
    /// feedback), and SwiftUI gives no way to enlarge that built-in one. Presenting
    /// our own `.graphical` DatePicker inside a plain `.popover` gets a full-size,
    /// easy-to-read calendar without adding any height to the window itself, since a
    /// popover floats above the window rather than growing it.
    private var dateRow: some View {
        HStack {
            Text("Date")
            Spacer()
            Button {
                isDatePickerPresented = true
            } label: {
                Text(Self.dateButtonFormatter.string(from: dueDate))
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $isDatePickerPresented, arrowEdge: .bottom) {
                // `.graphical` renders at a fixed intrinsic size regardless of the
                // frame wrapped around it — setting a bigger frame just adds empty
                // padding, not a bigger calendar (confirmed via screenshot). `.fixedSize()`
                // locks it to that natural size so `.scaleEffect` has something concrete
                // to scale up, and the outer frame is sized generously so the visually
                // enlarged calendar has room to render without being clipped.
                DatePicker("", selection: dateOnlyBinding, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .fixedSize()
                    .scaleEffect(1.35)
                    .frame(width: 380, height: 340)
            }
        }
        .font(.system(size: 14))
    }

    /// A calendar-only picker for the end date, mirroring `dateRow` exactly. Replaces
    /// what used to be a single combined date+time `.compact` DatePicker for "Custom"
    /// end times — that control had the exact same tiny-stepper, small-popover
    /// problems the start time already moved away from; it just hadn't been touched
    /// yet.
    private var endDateRow: some View {
        HStack {
            Text("End Date")
            Spacer()
            Button {
                isEndDatePickerPresented = true
            } label: {
                Text(Self.dateButtonFormatter.string(from: endDate))
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $isEndDatePickerPresented, arrowEdge: .bottom) {
                DatePicker("", selection: endDateOnlyBinding, in: dueDate..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .fixedSize()
                    .scaleEffect(1.35)
                    .frame(width: 380, height: 340)
            }
        }
        .font(.system(size: 14))
    }

    /// A single "HH:mm" field, 24-hour, directly typeable — replaces an earlier
    /// attempt at separate hour/minute controls side by side, which didn't fit this
    /// window's width and wrapped into a second, visually broken line (confirmed via
    /// screenshot). One field can't wrap, and the trailing clock menu offers a few
    /// nearby times for a single click without giving up manual entry. `.labelsHidden()`
    /// plus an explicit `prompt:` is required here — inside a `Form`, a plain
    /// `TextField("HH:mm", text:)` renders "HH:mm" as a permanent caption above the
    /// field rather than placeholder text that disappears once there's a value
    /// (confirmed via screenshot: it sat there even with "12:00" already entered).
    private var timeRow: some View {
        HStack {
            Text("Time")
            Spacer()
            HStack(spacing: 6) {
                TextField("", text: $timeText, prompt: Text("HH:mm"))
                    .labelsHidden()
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .focused($isTimeFieldFocused)
                    .onSubmit(commitTimeText)
                    .onChange(of: isTimeFieldFocused) { _, focused in
                        if !focused { commitTimeText() }
                    }

                Menu {
                    ForEach(Self.quickTimes(), id: \.label) { quickTime in
                        Button(quickTime.label) { applyQuickTime(hour: quickTime.hour, minute: quickTime.minute) }
                    }
                } label: {
                    Image(systemName: "clock.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Quick-pick a time near now")
            }
        }
        .font(.system(size: 14))
    }

    private var endTimeRow: some View {
        HStack {
            Text("End Time")
            Spacer()
            HStack(spacing: 6) {
                TextField("", text: $endTimeText, prompt: Text("HH:mm"))
                    .labelsHidden()
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .focused($isEndTimeFieldFocused)
                    .onSubmit(commitEndTimeText)
                    .onChange(of: isEndTimeFieldFocused) { _, focused in
                        if !focused { commitEndTimeText() }
                    }

                Menu {
                    ForEach([30, 60, 90, 120, 180], id: \.self) { minutesFromStart in
                        Button("+\(minutesFromStart)m") { applyQuickEndOffset(minutesFromStart) }
                    }
                } label: {
                    Image(systemName: "clock.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Quick-pick a duration from the start time")
            }
        }
        .font(.system(size: 14))
    }

    /// A custom binding rather than `$hasDueDate` plus `onChange`.
    ///
    /// `onChange` runs on the *next* view update, not at the moment the value changes.
    /// `loadIfNeeded` sets `hasDueDate` and `hasLoaded` together during `onAppear`, so
    /// by the time the handler ran, its `guard hasLoaded` had already stopped guarding
    /// anything: opening a reminder that already had a start time would fall into the
    /// "toggled on" branch and overwrite that start time with "now." A binding's setter
    /// only runs when the control is genuinely operated, so loading can never trip it.
    private var hasDueDateBinding: Binding<Bool> {
        Binding(
            get: { hasDueDate },
            set: { newValue in
                withAnimation {
                    hasDueDate = newValue
                    if newValue {
                        dueDate = Date.now.roundedUpToNearestFiveMinutes()
                        // Set explicitly: the row that keeps `timeText` in step with
                        // `dueDate` doesn't exist yet on the update that reveals it.
                        timeText = TimeOfDay(date: dueDate).formatted
                    } else {
                        durationPreset = .none
                        hasEndDate = false
                        checkInPreset = .none
                        repeatRule = .never
                    }
                }
            }
        )
    }

    /// Reads/writes only the date portion of `dueDate`, always recombining with the
    /// *existing* time-of-day rather than whatever SwiftUI's `.graphical` DatePicker
    /// would otherwise produce on its own. Binding the calendar directly to `$dueDate`
    /// was silently resetting the time to noon every time a day was tapped — even
    /// re-tapping the already-selected day — because a date-only `DatePicker` binding
    /// to a full `Date` constructs its new value with an unspecified time component,
    /// and unspecified time defaults to noon (confirmed via screenshot: a correct
    /// 15:00 became 12:00 after nothing but opening/using the calendar). Routing every
    /// calendar interaction through this binding makes that impossible — the time
    /// component is always explicitly carried over.
    private var dateOnlyBinding: Binding<Date> {
        Binding(
            get: { dueDate },
            set: { dueDate = Self.combining(date: $0, timeOf: dueDate) }
        )
    }

    private var endDateOnlyBinding: Binding<Date> {
        Binding(
            get: { endDate },
            set: { endDate = Self.combining(date: $0, timeOf: endDate) }
        )
    }

    private static func combining(date: Date, timeOf timeSource: Date) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute, .second], from: timeSource)
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return calendar.date(from: components) ?? date
    }

    private func applyQuickTime(hour: Int, minute: Int) {
        guard let time = TimeOfDay(hour: hour, minute: minute) else { return }
        dueDate = time.applied(to: dueDate)
        timeText = TimeOfDay(date: dueDate).formatted
    }

    private func applyQuickEndOffset(_ minutesFromStart: Int) {
        endDate = dueDate.addingTimeInterval(TimeInterval(minutesFromStart * 60))
        endTimeText = TimeOfDay(date: endDate).formatted
    }

    /// Applies whatever is currently typed in the start-time field, or snaps the text
    /// back to the stored value when it isn't a valid time. Runs on Enter and on focus
    /// loss so the field reflects reality as you use it; `save()` does not depend on it
    /// having run (see `resolvedSchedule`).
    private func commitTimeText() {
        guard let time = TimeOfDay(text: timeText) else {
            timeText = TimeOfDay(date: dueDate).formatted
            return
        }
        dueDate = time.applied(to: dueDate)
        timeText = TimeOfDay(date: dueDate).formatted
    }

    private func commitEndTimeText() {
        guard let time = TimeOfDay(text: endTimeText) else {
            endTimeText = TimeOfDay(date: endDate).formatted
            return
        }
        let candidate = time.applied(to: endDate)
        // An end time typed to be at-or-before the start is nonsensical. Push it an
        // hour past the start instead of silently accepting it, the same rule the
        // duration presets already enforce.
        endDate = candidate > dueDate ? candidate : dueDate.addingTimeInterval(3600)
        endTimeText = TimeOfDay(date: endDate).formatted
    }

    /// The start/end to actually persist, derived here and now from what's on screen.
    ///
    /// This deliberately re-reads the time fields rather than trusting `dueDate` /
    /// `endDate`, because those only catch up to typed text when the field loses focus.
    /// Clicking "Save Changes" straight after typing a time races with that focus
    /// change, so the first save could store the *previous* time while the typed one
    /// landed a moment later, in view state that was then reused on the next open. That
    /// is precisely why saving a second time appeared to fix it. Deriving the values
    /// synchronously removes the race instead of trying to win it.
    private func resolvedSchedule() -> (start: Date?, end: Date?) {
        guard hasDueDate else { return (nil, nil) }

        var start = dueDate
        if let typed = TimeOfDay(text: timeText) {
            start = typed.applied(to: dueDate)
        }

        guard hasEndDate else { return (start, nil) }

        if durationPreset == .custom {
            var end = endDate
            if let typedEnd = TimeOfDay(text: endTimeText) {
                end = typedEnd.applied(to: endDate)
            }
            return (start, end > start ? end : start.addingTimeInterval(3600))
        }

        // A preset duration always trails the start time, so recompute it from the
        // start we just resolved rather than from a stored value that a deferred
        // `onChange` may not have refreshed yet.
        if let interval = durationPreset.interval {
            return (start, start.addingTimeInterval(interval))
        }
        return (start, endDate > start ? endDate : start.addingTimeInterval(3600))
    }

    private func save() {
        let schedule = resolvedSchedule()
        store.update(
            itemID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            dueDate: schedule.start,
            endDate: schedule.end,
            tag: tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : tag,
            checkInIntervalMinutes: schedule.end != nil ? checkInPreset.minutes : nil,
            recurrenceRule: schedule.start != nil ? repeatRule.rule : nil
        )
        onDismiss()
    }

    private var scheduleFooterText: String {
        guard hasDueDate else {
            return "No start time set. This task has no due date and won't notify you."
        }
        guard notificationsEnabled else {
            return "Notifications are currently turned off in Preferences, so this won't alert you. It'll still show up in the right list, just silently."
        }
        if hasEndDate, checkInPreset != .none {
            return "Loop will notify you when it starts, then check in with you \(checkInPreset.rawValue.lowercased()) until it ends."
        }
        return hasEndDate
            ? "Loop will notify you when it starts. The end time is just for your reference."
            : "Loop will send you a notification at exactly this date and time."
    }

    private func loadIfNeeded() {
        guard !hasLoaded, let item = store.items.first(where: { $0.id == itemID }) else { return }
        title = item.title
        notes = item.notes ?? ""
        tag = item.tag ?? ""
        hasDueDate = item.dueDate != nil
        dueDate = item.dueDate ?? .now
        hasEndDate = item.endDate != nil
        endDate = item.endDate ?? dueDate.addingTimeInterval(3600)
        if let due = item.dueDate, let end = item.endDate {
            durationPreset = .matching(intervalSeconds: end.timeIntervalSince(due))
        } else {
            durationPreset = .none
        }
        checkInPreset = .matching(minutes: item.checkInIntervalMinutes)
        repeatRule = .matching(item.recurrenceRule)
        timeText = TimeOfDay(date: dueDate).formatted
        endTimeText = TimeOfDay(date: endDate).formatted
        hasLoaded = true
    }
}
