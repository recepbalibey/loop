import SwiftUI
import AppKit
import LoopKit

struct TaskRowView: View {
    var item: ReminderItem
    var isSelected: Bool = false
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onReschedule: (Date?) -> Void
    var onSetPriority: (Priority) -> Void
    var onEdit: () -> Void
    /// Called when another row's drag payload (a reminder's id, as a string) is
    /// dropped on this one — repositions that item to sit just before this one. See
    /// `TaskStore.moveItem`.
    var onReorder: (_ draggedID: ReminderItem.ID) -> Void
    var onSaveAsTemplate: () -> Void

    @Environment(NotificationAuthorization.self) private var notificationAuthorization
    @State private var isHovering = false
    @AppStorage(PreferenceKeys.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(PreferenceKeys.accentColorOption) private var accentColorOptionRaw = AccentColorOption.system.rawValue

    private var accentColor: Color { resolvedAccentColor(from: accentColorOptionRaw) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CheckboxButton(isCompleted: item.isCompleted, accentColor: accentColor, action: animatedToggle)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if item.priority != .none {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(priorityColor)
                            .help("\(item.priority.label) priority")
                    }
                    if item.recurrenceRule != nil {
                        Image(systemName: "repeat")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .help("Repeats")
                    }
                    Text(item.title)
                        .font(.system(size: 15, weight: .medium))
                        .strikethrough(item.isCompleted, color: .secondary)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                }

                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let tag = item.tag {
                    Text(tag)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            // Clicking the title/notes area completes the task too, not just the small
            // checkbox circle — a much more forgiving target for the primary action.
            .contentShape(Rectangle())
            .onTapGesture(perform: animatedToggle)

            Spacer(minLength: 8)

            // Quick actions that only appear on hover — reaching the same two most
            // common follow-ups (push to tomorrow, open the full editor) without
            // needing the right-click menu. Always in the tree at a fixed width so
            // showing/hiding them doesn't shift the row's layout, matching the same
            // pattern used for the bell/time content below.
            HStack(spacing: 6) {
                Button(action: { onReschedule(startOfTomorrow()) }) {
                    Image(systemName: "arrow.uturn.right.circle")
                }
                .help("Move to tomorrow")

                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                }
                .help("Edit")
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)

            // Both pieces here are unconditionally present in the view tree and
            // toggled via opacity/empty-string rather than `if`/`if let` — defensive
            // simplification alongside the VStack change above, ruling out any
            // conditional-view-identity edge case as the cause of a confirmed bug
            // where this trailing content failed to update for an existing row.
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .opacity(hasScheduledNotification ? 1 : 0)
                    .help("A notification is scheduled for this reminder")

                Text(rightSideLabel)
                    .font(.system(size: 13, weight: isOverdue(item.dueDate) ? .semibold : .regular))
                    .foregroundStyle(isOverdue(item.dueDate) ? .red : .secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        // A distinct outline for keyboard-selected rows — separate from the hover fill
        // above, since both can technically be true at once (hovering the keyboard's
        // current selection) and need to stay visually distinguishable.
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accentColor.opacity(isSelected ? 0.7 : 0), lineWidth: 1.5)
        )
        .tint(accentColor)
        // A faint lift on hover — small scale and shadow — so the list feels
        // responsive to the cursor rather than static, without being distracting.
        .scaleEffect(isHovering ? 1.008 : 1)
        .shadow(color: .black.opacity(isHovering ? 0.12 : 0), radius: isHovering ? 4 : 0, y: isHovering ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .onHover {
            isHovering = $0
            if $0 { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .draggable(item.id.uuidString)
        .dropDestination(for: String.self) { draggedIDStrings, _ in
            guard let draggedIDString = draggedIDStrings.first, let draggedID = UUID(uuidString: draggedIDString) else {
                return false
            }
            onReorder(draggedID)
            return true
        }
        .contextMenu {
            Button("Edit…", action: onEdit)
            Divider()
            Button("Today") { onReschedule(startOfToday()) }
            Button("Tomorrow") { onReschedule(startOfTomorrow()) }
            Button("No Date") { onReschedule(nil) }
            Divider()
            Menu("Priority") {
                ForEach(Priority.allCases.reversed()) { tier in
                    Button {
                        onSetPriority(tier)
                    } label: {
                        if item.priority == tier {
                            Label(tier.label, systemImage: "checkmark")
                        } else {
                            Text(tier.label)
                        }
                    }
                }
            }
            Button("Save as Template…", action: onSaveAsTemplate)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .none: return .clear
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func animatedToggle() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            onToggle()
        }
    }

    /// What to show at the trailing edge of the row. Any dated task always shows
    /// *something* here — a plain "Today"/"Tomorrow" as a fallback when there's no
    /// specific time, never silently nothing, since a blank trailing edge previously
    /// read as "this app doesn't show scheduling info at all." When an end time is
    /// also set, this becomes a "start – end" range instead of a single moment.
    private var rightSideLabel: String {
        guard let dueDate = item.dueDate else { return "" }
        let calendar = Calendar.current

        func hasTimeComponent(_ date: Date) -> Bool {
            calendar.component(.hour, from: date) != 0 || calendar.component(.minute, from: date) != 0
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        let startLabel: String
        switch item.section {
        case .today, .tomorrow:
            startLabel = hasTimeComponent(dueDate)
                ? timeFormatter.string(from: dueDate)
                : NaturalLanguageParser.dateChipLabel(for: dueDate)
        case .overdue, .thisWeek, .later:
            let datePart = dateFormatter.string(from: dueDate)
            startLabel = hasTimeComponent(dueDate) ? "\(datePart) \(timeFormatter.string(from: dueDate))" : datePart
        case .someday:
            return ""
        }

        guard let endDate = item.endDate else { return startLabel }

        if calendar.isDate(dueDate, inSameDayAs: endDate) {
            return "\(timeFormatter.string(from: dueDate)) – \(timeFormatter.string(from: endDate))"
        }
        let endDatePart = dateFormatter.string(from: endDate)
        return "\(startLabel) – \(endDatePart) \(timeFormatter.string(from: endDate))"
    }

    /// Whether this specific reminder actually has (or will get) a notification
    /// scheduled for it — not just "does it have a due date," but the same condition
    /// `NotificationScheduler` itself uses, so the bell never lies about what will
    /// really happen. That means both switches count: Loop's own preference, and whether
    /// macOS will deliver anything at all. The bell used to keep promising an alert even
    /// when the system had permission switched off.
    private var hasScheduledNotification: Bool {
        notificationsEnabled
            && !notificationAuthorization.status.blocksDelivery
            && item.needsScheduledNotification()
    }

    private func isOverdue(_ date: Date?) -> Bool {
        guard let date, !item.isCompleted else { return false }
        return date < Calendar.current.startOfDay(for: .now)
    }

    private func startOfToday() -> Date {
        Calendar.current.startOfDay(for: .now)
    }

    private func startOfTomorrow() -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfToday()) ?? .now
    }
}

/// The circular completion control — a hollow ring that fills with a checkmark when tapped.
struct CheckboxButton: View {
    var isCompleted: Bool
    var accentColor: Color = .accentColor
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isCompleted ? .clear : Color.secondary.opacity(0.5), lineWidth: 1.5)
                Circle()
                    .fill(isCompleted ? accentColor : .clear)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            // A stroked circle with no fill only hit-tests on the visible ring itself
            // without this — a click in the empty middle would silently do nothing,
            // which is exactly the "clicking the checkbox doesn't work" bug this fixes.
            // The extra padding also makes the tappable area more forgiving than the
            // small 18pt glyph alone.
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle())
        .onHover { $0 ? NSCursor.pointingHand.set() : NSCursor.arrow.set() }
    }
}

/// Scales a control down slightly while pressed and springs back on release — a small
/// piece of tactile feedback so tapping the checkbox (or anything else using this
/// style) feels like pressing something physical rather than toggling a flat glyph.
private struct BouncyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}
