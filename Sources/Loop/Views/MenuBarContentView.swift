import SwiftUI
import AppKit
import LoopKit

struct MenuBarContentView: View {
    @Environment(TaskStore.self) private var store
    @Environment(TemplateStore.self) private var templateStore
    @Environment(NotificationAuthorization.self) private var notificationAuthorization

    /// Hosted in a plain NSPopover, not a SwiftUI Scene, so window-opening actions are
    /// threaded in explicitly by AppDelegate rather than relying on environment actions
    /// like `openWindow`/`openSettings`, which aren't reliable outside a Scene context.
    var onEditRequested: (ReminderItem.ID) -> Void
    var onOpenPreferences: () -> Void
    var onRequestClose: () -> Void

    @State private var searchText = ""
    @State private var recentlyCompletedID: ReminderItem.ID?
    @State private var undoTask: Task<Void, Never>?
    @State private var isCompletedSectionExpanded = true
    @State private var isShowingClearConfirmation = false
    @State private var isAddRowHovering = false
    @State private var isGearHovering = false
    @State private var selectedItemID: ReminderItem.ID?
    @State private var activeTagFilter: String?
    @State private var activePriorityFilter: Priority?
    @AppStorage(PreferenceKeys.accentColorOption) private var accentColorOptionRaw = AccentColorOption.system.rawValue
    @FocusState private var isSearchFocused: Bool

    private var accentColor: Color { resolvedAccentColor(from: accentColorOptionRaw) }

    private var incompleteItems: [ReminderItem] {
        store.items.filter { !$0.isCompleted && matchesFilters($0) }
    }

    /// Most-recently-completed first. Kept visible (not just the transient Undo toast)
    /// so completing a task has lasting, checkable evidence it actually happened.
    private var completedItems: [ReminderItem] {
        store.items
            .filter { $0.isCompleted && matchesFilters($0) }
            .sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
    }

    /// Tag and priority filters combine with AND — picking both "home" and "High"
    /// narrows to items that are both, not either.
    private func matchesFilters(_ item: ReminderItem) -> Bool {
        if let activeTagFilter, item.tag != activeTagFilter { return false }
        if let activePriorityFilter, item.priority != activePriorityFilter { return false }
        return true
    }

    /// Every distinct tag currently in use, for the quick-filter chip row.
    private var allTags: [String] {
        Array(Set(store.items.compactMap(\.tag))).sorted()
    }

    /// The items keyboard up/down should move through — whatever's actually visible
    /// right now, in the same order the list shows them: search results while
    /// searching, otherwise every incomplete item in its normal grouped order.
    private var navigableItems: [ReminderItem] {
        parsed != nil ? matchingItems : groupedSections.flatMap(\.1)
    }

    private var recentlyCompleted: ReminderItem? {
        guard let recentlyCompletedID else { return nil }
        return store.items.first { $0.id == recentlyCompletedID }
    }

    private var trimmedInput: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsed: ParsedInput? {
        guard !trimmedInput.isEmpty else { return nil }
        return NaturalLanguageParser.parse(trimmedInput)
    }

    /// Searches everything, not just open tasks — completed items still show up (with
    /// their usual checkmark/strikethrough styling), since "did I already do this?" is
    /// a perfectly normal thing to search for.
    private var matchingItems: [ReminderItem] {
        guard !trimmedInput.isEmpty else { return [] }
        return store.items.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmedInput)
                || (item.notes?.localizedCaseInsensitiveContains(trimmedInput) ?? false)
                || (item.tag?.localizedCaseInsensitiveContains(trimmedInput) ?? false)
        }
    }

    /// How many of today's reminders are done — "today's" meaning due today (whether
    /// or not it's been completed yet) or completed today despite being due some other
    /// day (or no day at all). Purely a live snapshot of the current items, no separate
    /// history/streak storage.
    private var todayStats: (done: Int, total: Int) {
        let calendar = Calendar.current
        let relevant = store.items.filter { item in
            if let due = item.dueDate, calendar.isDateInToday(due) { return true }
            if let completed = item.completedDate, calendar.isDateInToday(completed) { return true }
            return false
        }
        return (relevant.filter(\.isCompleted).count, relevant.count)
    }

    /// New rows pop in with a gentle scale, rather than just appearing — removed rows
    /// just fade rather than scaling down, which reads more like "gone" than "shrank."
    private var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var groupedSections: [(ReminderSection, [ReminderItem])] {
        let groups = Dictionary(grouping: incompleteItems, by: \.section)
        return ReminderSection.allCases.compactMap { section in
            guard let items = groups[section], !items.isEmpty else { return nil }
            return (section, items.sorted(by: sortWithinSection))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Divider().opacity(0.5)

            permissionBanner

            tagFilterBar

            ScrollView {
                // Deliberately VStack, not LazyVStack: this list is small (a personal
                // reminders app, not a feed), and LazyVStack's virtualization/measurement
                // caching is a real suspect for a confirmed bug where an existing row
                // (same item identity) failed to show newly-added schedule info after
                // an edit — its content shape changed without the row being added or
                // removed. Plain VStack always fully re-evaluates every child on each
                // render pass, which trades a little perf headroom we don't need here
                // for eliminating that whole class of staleness.
                VStack(alignment: .leading, spacing: 4) {
                    if let parsed {
                        addSuggestionRow(parsed)
                        ForEach(matchingItems) { item in
                            row(for: item)
                        }
                    } else if incompleteItems.isEmpty && completedItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedSections, id: \.0) { section, items in
                            SectionHeaderView(title: section.rawValue)
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                row(for: item)
                                    .transition(rowTransition)
                                if index < items.count - 1 {
                                    Divider().opacity(0.15).padding(.leading, 32)
                                }
                            }
                        }
                        if !completedItems.isEmpty {
                            completedSection
                        }
                    }
                }
                .padding(12)
                // Drives every add/remove/reorder in the list above with one spring —
                // a new task pops in, a deleted one shrinks away, a completed one
                // sliding down into the Completed section all read as one continuous,
                // physical motion instead of an instant, flat swap.
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: store.items)
            }
            .frame(minHeight: 160, maxHeight: 480)

            if let recentlyCompleted {
                undoBar(for: recentlyCompleted)
                Divider().opacity(0.5)
            }

            footer
        }
        .frame(width: 440)
        .liquidGlass(cornerRadius: 20)
        .tint(accentColor)
        .onAppear { isSearchFocused = true }
        .onExitCommand(perform: onRequestClose) // Escape closes the panel, standard macOS convention
    }

    // MARK: - Rows

    private func row(for item: ReminderItem) -> some View {
        TaskRowView(
            item: item,
            isSelected: selectedItemID == item.id,
            onToggle: { toggle(item) },
            onDelete: { delete(item) },
            onReschedule: { store.reschedule(item.id, to: $0) },
            onSetPriority: { store.setPriority(item.id, $0) },
            onEdit: { onEditRequested(item.id) },
            onReorder: { draggedID in store.moveItem(draggedID, toBeBefore: item.id) },
            onSaveAsTemplate: { saveAsTemplate(item) }
        )
    }

    private func addSuggestionRow(_ parsed: ParsedInput) -> some View {
        Button(action: addTask) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(accentColor)
                    .font(.system(size: 17))

                Text(parsed.cleanTitle)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                if let date = parsed.date {
                    Chip(systemImage: "calendar", text: NaturalLanguageParser.dateChipLabel(for: date), color: accentColor)
                }
                if let tag = parsed.tag {
                    Chip(systemImage: "location.fill", text: tag, color: .orange)
                }

                Image(systemName: "return")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle()) // the Spacer's empty middle is otherwise unclickable
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accentColor.opacity(isAddRowHovering ? 0.14 : 0.08))
        )
        .scaleEffect(isAddRowHovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.12), value: isAddRowHovering)
        .onHover {
            isAddRowHovering = $0
            $0 ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
        }
    }

    /// A disclosure group rather than a plain always-open list so a long history of
    /// completed items doesn't dominate the panel — but starts expanded, since hiding
    /// completed work by default is exactly what made completing something feel like
    /// it vanished into nothing.
    private var completedSection: some View {
        DisclosureGroup(isExpanded: $isCompletedSectionExpanded) {
            ForEach(completedItems) { item in
                row(for: item)
            }
        } label: {
            HStack {
                Text("COMPLETED (\(completedItems.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { isShowingClearConfirmation = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accentColor)
                    .confirmationDialog(
                        "Clear \(completedItems.count) completed reminder\(completedItems.count == 1 ? "" : "s")?",
                        isPresented: $isShowingClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear Completed", role: .destructive, action: store.clearCompleted)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This can't be undone.")
                    }
            }
        }
        .padding(.top, 8)
    }

    /// Surfaces a blocked permission where it cannot be missed. Loop can schedule
    /// notifications all it likes; if macOS has been told not to deliver them, none of
    /// it happens. Previously that failed completely silently, so a reminder simply
    /// never arrived and nothing explained why.
    @ViewBuilder
    private var permissionBanner: some View {
        if notificationAuthorization.status.blocksDelivery {
            HStack(spacing: 8) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)

                Text("macOS is blocking Loop's notifications, so reminders won't alert you.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Button("Open Settings") {
                    NotificationAuthorization.openSystemSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .onHover { $0 ? NSCursor.pointingHand.set() : NSCursor.arrow.set() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.orange.opacity(0.12))

            Divider().opacity(0.5)
        }
    }

    private var hasActiveFilter: Bool {
        activeTagFilter != nil || activePriorityFilter != nil
    }

    /// Two different empty states, because "you're all clear" and "a filter is hiding
    /// everything" are opposite situations. Showing the congratulatory one while a
    /// filter was active was actively misleading: the list could be full of pending work
    /// and still claim there was nothing to do, with no hint that a chip was responsible.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle" : "checkmark.circle")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)

            if hasActiveFilter {
                Text("Nothing matches this filter.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Button("Clear filters") {
                    withAnimation(.easeOut(duration: 0.15)) {
                        activeTagFilter = nil
                        activePriorityFilter = nil
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accentColor)
                .onHover { $0 ? NSCursor.pointingHand.set() : NSCursor.arrow.set() }
            } else {
                Text("Nothing pending. Nice.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Type above to add your next one, try “tomorrow at 3pm”")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func undoBar(for item: ReminderItem) -> some View {
        HStack {
            Text("Completed “\(item.title)”")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Undo", action: undo)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isSearchFocused ? accentColor : .secondary)
            TextField("Search or add a reminder", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .onSubmit(addTask)
                // Down/Up move a keyboard selection through the visible list without
                // leaving the search field — Spotlight-style. Return either completes
                // the selected row, or falls through to `onSubmit`/`addTask` above when
                // nothing's selected.
                .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
                .onKeyPress(.return) {
                    guard let selectedItemID, let item = store.items.first(where: { $0.id == selectedItemID }) else {
                        return .ignored
                    }
                    toggle(item)
                    return .handled
                }
                .onChange(of: searchText) { _, _ in selectedItemID = nil } // stale selection from a different list would be confusing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        // A soft glow along the bottom edge when focused — a small "this surface is
        // alive and listening" cue rather than a plain static bar.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accentColor.opacity(isSearchFocused ? 0.6 : 0))
                .frame(height: 1.5)
        }
        .animation(.easeOut(duration: 0.2), value: isSearchFocused)
        // Invisible — exists purely to give ⌘Z a global handler for undoing the most
        // recent completion, without requiring the Undo bar's own button to have focus.
        .background(
            Button(action: undo) { EmptyView() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(recentlyCompletedID == nil)
                .opacity(0)
        )
    }

    /// Every priority tier actually in use right now (excluding `.none`, which isn't
    /// interesting to filter down to), high to low.
    private var usedPriorities: [Priority] {
        Priority.allCases
            .filter { $0 != .none }
            .filter { tier in store.items.contains { $0.priority == tier } }
            .sorted(by: >)
    }

    private func priorityColor(_ tier: Priority) -> Color {
        switch tier {
        case .none: return .secondary
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    /// Horizontally-scrolling tag and priority chips — tapping one filters the list
    /// down (the two combine with AND); tapping an active one again clears just that
    /// filter. Hidden while typing a search/add, since it'd otherwise compete with the
    /// add-suggestion row for the same space right below the search field.
    @ViewBuilder
    private var tagFilterBar: some View {
        if (!allTags.isEmpty || !usedPriorities.isEmpty), parsed == nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(usedPriorities) { tier in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                activePriorityFilter = (activePriorityFilter == tier) ? nil : tier
                            }
                        } label: {
                            Chip(
                                systemImage: "flag.fill",
                                text: tier.label,
                                color: activePriorityFilter == tier ? priorityColor(tier) : .secondary
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                activeTagFilter = (activeTagFilter == tag) ? nil : tag
                            }
                        } label: {
                            Chip(systemImage: "tag.fill", text: tag, color: activeTagFilter == tag ? accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 6)

            Divider().opacity(0.5)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if todayStats.total > 0 {
                todayProgressRing
                Text("\(todayStats.done)/\(todayStats.total) today")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Menu {
                if templateStore.templates.isEmpty {
                    Text("No templates yet")
                } else {
                    ForEach(templateStore.templates) { template in
                        Menu(template.title) {
                            Button("Add Reminder", action: { applyTemplate(template) })
                            Button("Delete Template", role: .destructive) { templateStore.delete(template.id) }
                        }
                    }
                }
            } label: {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Templates — right-click a reminder and choose “Save as Template…” to add one")

            Menu {
                Button("Preferences…", action: onOpenPreferences)
                    .keyboardShortcut(",", modifiers: .command)
                Divider()
                Button("Quit Loop") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(isGearHovering ? Color.primary : Color.secondary)
                    .rotationEffect(.degrees(isGearHovering ? 25 : 0))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isGearHovering)
            .onHover {
                isGearHovering = $0
                $0 ? NSCursor.pointingHand.set() : NSCursor.arrow.set()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// A tiny animated ring mirroring `todayStats` — the same "faint track, solid
    /// progress arc" idea as the menu bar icon's own progress ring, just in SwiftUI
    /// this time since it's rendered inline rather than as a status item glyph.
    private var todayProgressRing: some View {
        let stats = todayStats
        let fraction = stats.total == 0 ? 0 : Double(stats.done) / Double(stats.total)
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .animation(.easeInOut(duration: 0.4), value: fraction)
    }

    // MARK: - Actions

    private func addTask() {
        guard let parsed, !parsed.cleanTitle.isEmpty else { return }
        store.add(title: parsed.cleanTitle, dueDate: parsed.date, tag: parsed.tag)
        searchText = ""
    }

    private func toggle(_ item: ReminderItem) {
        store.toggleCompletion(item.id)
        // A recurring item never actually becomes `isCompleted` — completing it just
        // advances it to its next occurrence (see `TaskStore.toggleCompletion`). The
        // Undo bar's action is `toggleCompletion` again, which for a recurring item
        // would advance it a *second* time instead of reverting the first — so skip
        // offering Undo for these rather than let it do the wrong thing.
        if !item.isCompleted, item.recurrenceRule == nil {
            showUndo(for: item.id)
        } else if recentlyCompletedID == item.id {
            undoTask?.cancel()
            withAnimation { recentlyCompletedID = nil }
        }
    }

    private func delete(_ item: ReminderItem) {
        if recentlyCompletedID == item.id { recentlyCompletedID = nil }
        store.delete(item.id)
    }

    private func showUndo(for id: ReminderItem.ID) {
        undoTask?.cancel()
        withAnimation { recentlyCompletedID = id }
        undoTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { recentlyCompletedID = nil }
        }
    }

    private func undo() {
        guard let id = recentlyCompletedID else { return }
        store.toggleCompletion(id)
        undoTask?.cancel()
        withAnimation { recentlyCompletedID = nil }
    }

    /// Captures everything about this reminder except *when* it happens — the
    /// duration is kept (as minutes, not a fixed end date), since a template's whole
    /// point is being reused on some other day.
    private func saveAsTemplate(_ item: ReminderItem) {
        let durationMinutes: Int?
        if let due = item.dueDate, let end = item.endDate {
            durationMinutes = Int(end.timeIntervalSince(due) / 60)
        } else {
            durationMinutes = nil
        }
        templateStore.add(title: item.title, notes: item.notes, tag: item.tag, durationMinutes: durationMinutes, priority: item.priority)
    }

    /// Applying a template creates a new reminder right now: if the template has a
    /// duration, that becomes a "starting now" scheduled block; otherwise it's added
    /// undated, same as typing a plain title with no date into the search field.
    private func applyTemplate(_ template: ReminderTemplate) {
        var dueDate: Date?
        var endDate: Date?
        if let minutes = template.durationMinutes, minutes > 0 {
            let start = Date.now.roundedUpToNearestFiveMinutes()
            dueDate = start
            endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        }
        store.add(title: template.title, notes: template.notes, dueDate: dueDate, endDate: endDate, tag: template.tag, priority: template.priority)
    }

    /// Priority first (high to low), then manual order — each item's position in
    /// `store.items` — as the tiebreak within a priority tier. This replaced a purely
    /// time-based sort: once priority levels and drag-to-reorder both exist, "soonest
    /// due time first" and "wherever the user dragged it" would otherwise fight each
    /// other every time the list re-renders. Coarse date grouping (Today/Tomorrow/…)
    /// still comes from `section`, unaffected by this — only the order *within* a
    /// section changed.
    private func sortWithinSection(_ lhs: ReminderItem, _ rhs: ReminderItem) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        guard let lhsIndex = store.items.firstIndex(of: lhs), let rhsIndex = store.items.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }

    // MARK: - Keyboard navigation

    private func moveSelection(by delta: Int) {
        let items = navigableItems
        guard !items.isEmpty else { return }
        guard let currentID = selectedItemID, let currentIndex = items.firstIndex(where: { $0.id == currentID }) else {
            selectedItemID = delta > 0 ? items.first?.id : items.last?.id
            return
        }
        let newIndex = min(max(currentIndex + delta, 0), items.count - 1)
        selectedItemID = items[newIndex].id
    }
}

private struct SectionHeaderView: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}
