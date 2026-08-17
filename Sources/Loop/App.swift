import SwiftUI
import AppKit
import Carbon.HIToolbox
import Observation
import UserNotifications
import UniformTypeIdentifiers
import LoopKit

@main
struct LoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // No SwiftUI Scene actually presents anything — the status item, popover, edit
    // window, and preferences window are all owned and shown directly by AppDelegate.
    // This keeps window-opening deterministic instead of depending on `openWindow` /
    // `openSettings` / `dismiss` environment actions, which assume the triggering view
    // is hosted inside a proper SwiftUI Scene — ours is hosted in a plain NSPopover.
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    let store = TaskStore()
    let templateStore = TemplateStore()
    let notificationAuthorization = NotificationAuthorization()
    private let notificationScheduler = NotificationScheduler()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private var editWindow: NSWindow?
    private var editHostingController: NSHostingController<AnyView>?
    private var editPresentationCount = 0

    private var preferencesWindow: NSWindow?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?

    private var overdueRefreshTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: [PreferenceKeys.notificationsEnabled: true])
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard enforceSingleInstance() else { return }
        setupStatusItem()
        setupPopover()
        registerGlobalHotKey()
        notificationScheduler.registerCategories()
        notificationAuthorization.requestIfNeeded()
        notificationScheduler.sync(with: store.items) // cover state from before this launch
        observeStoreChanges()
        startOverdueRefreshTimer()
    }

    /// Permission can be revoked in System Settings while Loop is running, and nothing
    /// notifies the app when it happens. Re-checking whenever Loop is activated keeps the
    /// warning in the panel truthful instead of stale.
    func applicationDidBecomeActive(_ notification: Notification) {
        notificationAuthorization.refresh()
    }

    /// `hasOverdueItems` is a computed property based on the current time, but the icon
    /// only gets recomputed when `store.items` actually mutates (see `observeStoreChanges`).
    /// If Loop just sits running in the background, a reminder can quietly cross from
    /// "Today" into "Overdue" with no data change at all to trigger that — the icon
    /// would then stay stale (not red) until the user happens to add/complete/delete
    /// something. A minute-granularity timer closes that gap without needing to predict
    /// exactly when the next reminder becomes overdue.
    private func startOverdueRefreshTimer() {
        overdueRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateStatusItemIcon()
        }
    }

    /// If Loop is somehow launched twice — a login item plus a manual double-click from
    /// Finder, say — the second instance would create a second, redundant status item.
    /// Quit the newcomer instead and let the original keep running.
    private func enforceSingleInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return true }
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard instances.count > 1 else { return true }
        NSApp.terminate(nil)
        return false
    }

    // MARK: - Status item & popover

    private func setupStatusItem() {
        // `.variableLength`, not `.squareLength` — squareLength is a *fixed* narrow
        // width sized for an icon alone. With it, switching to live-text mode crushed
        // the title into that same tiny square, wrapping "45m left" into an
        // unreadable "m\nleft" stacked over neighboring menu bar icons (confirmed via
        // screenshot). `.variableLength` sizes the item to fit whatever's actually in
        // the button — a plain icon or a full text label — either way.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        // A status item button only reports left clicks unless it is asked to do
        // otherwise. Earlier attempts here inspected `NSApp.currentEvent` for a
        // `.rightMouseUp` that was never being delivered in the first place, which is
        // why they looked correct and still did nothing. This is the piece that was
        // missing, and it has to come after target/action are set.
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusItemIcon()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        // Control-click is the long-standing macOS equivalent of a right-click, and
        // trackpads without a configured secondary click still produce it.
        let isSecondaryClick = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)

        if isSecondaryClick {
            showStatusItemMenu()
        } else {
            togglePopover(sender)
        }
    }

    /// Shows the secondary menu by handing it to the status item and clicking it, rather
    /// than calling `NSMenu.popUp` at a computed point. Routing it this way lets AppKit
    /// anchor, size, highlight, and dismiss the menu exactly as it does for every other
    /// menu bar item, including keyboard navigation.
    ///
    /// The menu is detached again in `menuDidClose` rather than on the line after
    /// `performClick`. That call is expected to block for the menu's nested tracking
    /// loop, but relying on it would mean the menu is torn down instantly if it ever
    /// returned early — the same "right-click does nothing" symptom this is meant to
    /// fix. Detaching on close is correct either way. It has to happen at some point,
    /// because a status item with a menu attached opens that menu on a plain left click
    /// instead of running our action, which would leave the panel unreachable.
    private func showStatusItemMenu() {
        popover?.performClose(nil)

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Loop", action: #selector(openPanelFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        let preferences = menu.addItem(withTitle: "Preferences…", action: #selector(openPreferencesFromMenu), keyEquivalent: ",")
        preferences.keyEquivalentModifierMask = .command
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Loop", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        for menuItem in menu.items where menuItem.action != nil {
            menuItem.target = self
        }

        menu.delegate = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Deferred: AppKit is still unwinding its menu tracking when this fires, and
        // detaching the menu out from under it there can leave the status item's
        // highlight stuck on.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    @objc private func openPanelFromMenu() {
        togglePopover(nil)
    }

    @objc private func openPreferencesFromMenu() {
        showPreferences()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    /// Keeps the menu bar glyph and scheduled notifications in sync with the store on
    /// every change: recolors the icon red while something's overdue, and reconciles
    /// which reminders have a pending notification. Re-arms itself each time via
    /// `withObservationTracking`, the supported way to observe an `@Observable` object
    /// outside of SwiftUI.
    private func observeStoreChanges() {
        withObservationTracking {
            _ = store.items
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusItemIcon()
                self?.notificationScheduler.sync(with: self?.store.items ?? [])
                self?.observeStoreChanges()
            }
        }
    }

    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let showsText = UserDefaults.standard.bool(forKey: PreferenceKeys.menuBarShowsText)

        if let active = activeScheduledItem() {
            let fraction = progressFraction(for: active)
            if showsText, let end = active.endDate {
                button.image = nil
                button.title = "\(Self.truncatedTitle(active.title)) · \(Self.remainingLabel(until: end))"
            } else {
                button.image = Self.progressRingImage(fraction: fraction)
                button.title = ""
            }
            button.toolTip = "\(active.title) · \(Int(fraction * 100))% through"
        } else if showsText, let next = nextUpcomingItem(), let due = next.dueDate {
            button.image = nil
            button.title = "\(Self.truncatedTitle(next.title)) · \(Self.startingLabel(for: due))"
            button.toolTip = next.title
        } else if store.hasOverdueItems {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Loop, overdue reminders")?
                .withSymbolConfiguration(config)
            image?.isTemplate = false
            button.image = image
            button.title = ""
            button.toolTip = nil
        } else {
            let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Loop")
            image?.isTemplate = true
            button.image = image
            button.title = ""
            button.toolTip = nil
        }
    }

    /// The one incomplete reminder, if any, whose scheduled block is happening right
    /// now — i.e. `dueDate <= now <= endDate`. At most one is shown at a time; if
    /// several overlap, the first one found wins, since the menu bar only has room for
    /// a single glyph anyway.
    private func activeScheduledItem() -> ReminderItem? {
        let now = Date.now
        return store.items.first { item in
            guard !item.isCompleted, let due = item.dueDate, let end = item.endDate else { return false }
            return due <= now && now <= end
        }
    }

    /// The soonest-due incomplete reminder that hasn't started yet — what "live text"
    /// mode shows in the menu bar when nothing's currently active.
    private func nextUpcomingItem() -> ReminderItem? {
        let now = Date.now
        return store.items
            .filter { !$0.isCompleted && ($0.dueDate ?? .distantPast) > now }
            .min { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private static func truncatedTitle(_ title: String, maxLength: Int = 22) -> String {
        title.count > maxLength ? "\(title.prefix(maxLength))…" : title
    }

    private static func remainingLabel(until end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSinceNow / 60))
        guard minutes >= 60 else { return "\(minutes)m left" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h left" : "\(hours)h \(remainder)m left"
    }

    private static func startingLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func progressFraction(for item: ReminderItem) -> CGFloat {
        guard let due = item.dueDate, let end = item.endDate, end > due else { return 0 }
        let total = end.timeIntervalSince(due)
        let elapsed = Date.now.timeIntervalSince(due)
        return CGFloat(min(max(elapsed / total, 0), 1))
    }

    /// Draws a small ring glyph for the status item — a faint full-circle track plus a
    /// solid arc for the completed fraction. Template mode lets macOS recolor it for
    /// light/dark menu bars automatically while still preserving the two different
    /// alpha values, so the track reads as background and the progress arc as
    /// foreground without needing separate light/dark art.
    private static func progressRingImage(fraction: CGFloat) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let lineWidth: CGFloat = 2.2
        let rect = NSRect(x: lineWidth / 2, y: lineWidth / 2, width: size.width - lineWidth, height: size.height - lineWidth)

        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(0.25).setStroke()
        track.stroke()

        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius = rect.width / 2
        let progress = NSBezierPath()
        progress.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * Double(fraction),
            clockwise: true
        )
        progress.lineWidth = lineWidth
        progress.lineCapStyle = .round
        NSColor.black.setStroke()
        progress.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        // Deliberately not setting `contentSize` here. An earlier attempt at actively
        // resizing the popover to fit content (on every store change, and reactively
        // while already open) caused it to visibly jump position on screen — resizing
        // a *shown* NSPopover can make it recompute which edge/position it needs to
        // stay on-screen, not just grow or shrink in place. Left alone, NSPopover sizes
        // itself once from the hosting controller's fitting size when it's shown, which
        // is stable. The SwiftUI content's own min/max frame (see MenuBarContentView)
        // is what controls how big that ends up being.
        popover.contentViewController = NSHostingController(rootView: makeMenuBarContentView())
        self.popover = popover
    }

    private func makeMenuBarContentView() -> some View {
        MenuBarContentView(
            onEditRequested: { [weak self] id in self?.showEditWindow(for: id) },
            onOpenPreferences: { [weak self] in self?.showPreferences() },
            onRequestClose: { [weak self] in self?.popover?.performClose(nil) }
        )
        .environment(store)
        .environment(templateStore)
        .environment(notificationAuthorization)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Edit window

    private func showEditWindow(for id: ReminderItem.ID) {
        popover?.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Bumped per presentation so every open gets a brand-new SwiftUI identity.
        // Keying on the reminder's `id` alone was not enough: reopening the *same*
        // reminder kept the previous view's `@State`, so `EditTaskView.loadIfNeeded`
        // saw `hasLoaded == true` and never re-read the store. That left the window
        // showing values from the last session, which is why editing a time, saving,
        // and reopening looked like it needed a second save to stick, and it would
        // also quietly revert a reschedule made from the list in between.
        editPresentationCount += 1
        let rootView = AnyView(
            EditTaskView(itemID: id, onDismiss: { [weak self] in self?.closeEditWindow() })
                .environment(store)
                .id("\(id.uuidString)-\(editPresentationCount)")
        )

        if let editHostingController {
            editHostingController.rootView = rootView
        } else {
            let hosting = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Edit Reminder"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            // `hosting.view.fittingSize` is not reliable here — it previously produced
            // a window narrow enough that a window *toolbar* silently collapsed "Save
            // Changes" behind an overflow chevron, with no visible save button at all
            // (confirmed via screenshot, not a guess). EditTaskView no longer uses a
            // toolbar for exactly that reason (its Save/Cancel/Delete bar is laid out
            // directly in the view), but the explicit-size lesson still applies: set
            // the exact size EditTaskView's own `.frame(width:height:)` declares
            // instead of trusting AppKit to measure it.
            window.setContentSize(NSSize(width: 380, height: 480))
            editWindow = window
            editHostingController = hosting
        }

        positionEditWindowTopRight()
        editWindow?.makeKeyAndOrderFront(nil)
    }

    /// Opens (and reopens) the Edit window just under the menu bar on the right side
    /// of the screen — near where the status item itself lives — rather than centered
    /// or vertically middled, so it consistently lands somewhere predictable and out
    /// of the way of whatever's already on screen.
    private func positionEditWindowTopRight() {
        guard let window = editWindow else { return }
        guard let screen = window.screen ?? NSScreen.main else {
            window.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let windowFrame = window.frame
        let x = visibleFrame.maxX - windowFrame.width - 12
        let y = visibleFrame.maxY - windowFrame.height - 8
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func closeEditWindow() {
        editWindow?.orderOut(nil)
    }

    // MARK: - Preferences window

    private func showPreferences() {
        popover?.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)

        if preferencesWindow == nil {
            let hosting = NSHostingController(rootView: PreferencesView(
                dataFileURL: store.fileURL,
                onNotificationsPreferenceChanged: { [weak self] in
                    guard let self else { return }
                    self.notificationScheduler.sync(with: self.store.items)
                },
                onSendTestNotification: { [weak self] in
                    self?.notificationScheduler.sendTestNotification()
                },
                onExportRequested: { [weak self] in
                    MarkdownExport.checklist(for: self?.store.items ?? [])
                },
                onICSExportRequested: { [weak self] in
                    self?.exportICS()
                },
                onMenuBarStyleChanged: { [weak self] in
                    self?.updateStatusItemIcon()
                },
                onHotKeyChanged: { [weak self] in
                    self?.applyCurrentHotKeyBinding()
                },
                notificationAuthorization: notificationAuthorization
            ))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Loop Preferences"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            // Same fix as the Edit window: an explicit size matching PreferencesView's
            // own `.frame(width:height:)`, not `fittingSize`.
            window.setContentSize(NSSize(width: 380, height: 700))
            preferencesWindow = window
        }

        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    /// Presents a standard save panel and writes the current reminders out as .ics.
    /// This is a plain, user-initiated "Export…" action in the app's own Preferences —
    /// the save location is always the user's own explicit choice via the system panel,
    /// nothing is written anywhere without them picking it right there.
    private func exportICS() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Loop Reminders.ics"
        panel.allowedContentTypes = [.init(filenameExtension: "ics") ?? .data]
        panel.canCreateDirectories = true

        guard let preferencesWindow else {
            presentICSPanel(panel)
            return
        }
        panel.beginSheetModal(for: preferencesWindow) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.writeICS(to: url)
        }
    }

    private func presentICSPanel(_ panel: NSSavePanel) {
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeICS(to: url)
    }

    private func writeICS(to url: URL) {
        let contents = ICSExport.calendar(for: store.items)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("Loop: failed to write .ics export: \(error)")
        }
    }

    // MARK: - Global hotkey (⌥⌘L by default, customizable in Preferences)

    private func registerGlobalHotKey() {
        installHotKeyEventHandlerIfNeeded()
        applyCurrentHotKeyBinding()
    }

    private func installHotKeyEventHandlerIfNeeded() {
        guard hotKeyHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.togglePopover(nil)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )
    }

    /// (Re-)registers the actual key combination from `UserDefaults`, falling back to
    /// the original ⌥⌘L when nothing's been customized. Called once at launch and
    /// again whenever Preferences records a new shortcut — unregistering the old
    /// binding first, since `RegisterEventHotKey` doesn't replace one in place.
    private func applyCurrentHotKeyBinding() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        let defaults = UserDefaults.standard
        let keyCode: UInt32 = defaults.object(forKey: PreferenceKeys.hotKeyCode) != nil
            ? UInt32(defaults.integer(forKey: PreferenceKeys.hotKeyCode))
            : UInt32(kVK_ANSI_L)
        let storedModifiers = defaults.object(forKey: PreferenceKeys.hotKeyModifierFlags) != nil
            ? NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: PreferenceKeys.hotKeyModifierFlags)))
            : [.option, .command]

        var carbonModifiers: UInt32 = 0
        if storedModifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if storedModifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if storedModifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if storedModifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("LOOP"), id: 1)
        RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Without this, macOS silently swallows notifications while Loop is the active
    /// (frontmost) app — which happens often here since opening the popover activates
    /// it. Reminders should still show even then.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        // Check-ins register under a suffixed identifier, so parsing the raw string as
        // a UUID only ever worked for a reminder's opening alert. Every button on a
        // check-in notification silently did nothing, and clicking the banner didn't
        // even open the panel, because the failed parse bailed out before the switch.
        let id = NotificationIdentifier.reminderID(from: response.notification.request.identifier)

        switch response.actionIdentifier {
        case NotificationScheduler.markDoneActionID:
            guard let id else { return }
            store.toggleCompletion(id)
        case NotificationScheduler.snoozeActionID:
            guard let id else { return }
            store.reschedule(id, to: Date().addingTimeInterval(NotificationScheduler.snoozeInterval))
        default:
            // Default click (or the app icon) — bring the panel up so they can act on it.
            DispatchQueue.main.async { [weak self] in self?.togglePopover(nil) }
        }
    }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for byte in string.utf8.prefix(4) {
        result = (result << 8) + FourCharCode(byte)
    }
    return result
}
