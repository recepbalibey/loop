import SwiftUI
import AppKit

struct PreferencesView: View {
    var dataFileURL: URL
    var onNotificationsPreferenceChanged: () -> Void
    var onSendTestNotification: () -> Void
    /// Returns the Markdown checklist to copy — a closure rather than the raw items so
    /// this view doesn't need `TaskStore` injected just for one button.
    var onExportRequested: () -> String
    /// Presents a save panel and writes the .ics file — handled entirely by
    /// AppDelegate (it needs a window to attach the panel to), so this view just
    /// triggers it.
    var onICSExportRequested: () -> Void
    /// Called after `menuBarShowsText` changes — AppDelegate owns the actual status
    /// item and needs to redraw it immediately rather than wait for the next
    /// data-driven or timer-driven refresh.
    var onMenuBarStyleChanged: () -> Void
    /// Called after a new shortcut is recorded — AppDelegate owns the actual Carbon
    /// hotkey registration and needs to unregister/re-register it immediately.
    var onHotKeyChanged: () -> Void
    var onWorkLogPreferenceChanged: () -> Void
    var notificationAuthorization: NotificationAuthorization

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(PreferenceKeys.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(PreferenceKeys.menuBarShowsText) private var menuBarShowsText = false
    @AppStorage(PreferenceKeys.accentColorOption) private var accentColorOptionRaw = AccentColorOption.system.rawValue
    @AppStorage(PreferenceKeys.notificationSoundOption) private var notificationSoundOptionRaw = NotificationSoundOption.system.rawValue
    @AppStorage(PreferenceKeys.hotKeyCode) private var hotKeyCode = 37 // kVK_ANSI_L
    @AppStorage(PreferenceKeys.hotKeyModifierFlags) private var hotKeyModifierFlags = Int(NSEvent.ModifierFlags([.option, .command]).rawValue)
    @AppStorage(PreferenceKeys.workLogEnabled) private var workLogEnabled = false
    @AppStorage(PreferenceKeys.workLogIntervalMinutes) private var workLogIntervalMinutes = 60
    @AppStorage(PreferenceKeys.workLogStartHour) private var workLogStartHour = 9
    @AppStorage(PreferenceKeys.workLogStartMinute) private var workLogStartMinute = 0
    @AppStorage(PreferenceKeys.workLogEndHour) private var workLogEndHour = 23
    @AppStorage(PreferenceKeys.workLogEndMinute) private var workLogEndMinute = 0
    @StateObject private var hotKeyRecorder = HotKeyRecorder()
    @State private var didCopyExport = false

    private var hotKeyLabel: String {
        HotKeyFormatter.label(keyCode: UInt16(hotKeyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(hotKeyModifierFlags)))
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var workLogIntervalSelection: Int {
        [45, 60, 90].contains(workLogIntervalMinutes) ? workLogIntervalMinutes : 0
    }

    private func setWorkLogIntervalSelection(_ value: Int) {
        if value == 0 {
            if [45, 60, 90].contains(workLogIntervalMinutes) { workLogIntervalMinutes = 120 }
        } else {
            workLogIntervalMinutes = value
        }
        onWorkLogPreferenceChanged()
    }

    private func workLogTimePicker(label: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Picker("Hour", selection: hour) {
                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 62)
            Text(":")
                .foregroundStyle(.secondary)
            Picker("Minute", selection: minute) {
                ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 62)
        }
    }

    /// `NSSound(named:)` plays the same system alert sound resources
    /// `UNNotificationSound(named:)` schedules notifications with, so this preview is
    /// an accurate preview of what a real reminder will actually sound like — not a
    /// guess. "Default" has no direct system-sound equivalent to preview with, so it
    /// falls back to the classic system alert beep instead of playing nothing.
    private func previewSound() {
        let option = NotificationSoundOption.resolved(from: notificationSoundOptionRaw)
        if option == .system {
            NSSound.beep()
        } else {
            NSSound(named: option.rawValue)?.play()
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch Loop at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.set(newValue)
                    }
                Toggle("Notify me when reminders are due", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, _ in
                        onNotificationsPreferenceChanged()
                    }
                HStack {
                    Picker("Sound", selection: $notificationSoundOptionRaw) {
                        ForEach(NotificationSoundOption.allCases) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                    .disabled(!notificationsEnabled)

                    Button {
                        previewSound()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!notificationsEnabled)
                    .help("Preview this sound")
                }
                Button("Send Test Notification", action: onSendTestNotification)
                    .disabled(!notificationsEnabled)

                if notificationAuthorization.status.blocksDelivery {
                    // Loop's own switch can be on while macOS refuses to deliver
                    // anything, which looks identical from in here without this.
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("macOS is blocking Loop's notifications.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings") {
                            NotificationAuthorization.openSystemSettings()
                        }
                    }
                }
            } header: {
                Text("General")
            } footer: {
                Text("Loop lives only in the menu bar. Your reminders are stored locally on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Ask for work updates", isOn: $workLogEnabled)
                    .onChange(of: workLogEnabled) { _, _ in onWorkLogPreferenceChanged() }

                Picker("Prompt every", selection: Binding(
                    get: { workLogIntervalSelection },
                    set: setWorkLogIntervalSelection
                )) {
                    Text("45 minutes").tag(45)
                    Text("60 minutes").tag(60)
                    Text("90 minutes").tag(90)
                    Text("Custom").tag(0)
                }
                .disabled(!workLogEnabled)

                if workLogIntervalSelection == 0 {
                    Stepper(value: Binding(
                        get: { workLogIntervalMinutes },
                        set: { newValue in
                            workLogIntervalMinutes = newValue
                            onWorkLogPreferenceChanged()
                        }
                    ), in: 30...480, step: 15) {
                        Text("Custom interval: \(workLogIntervalMinutes) minutes")
                    }
                    .disabled(!workLogEnabled)
                }

                workLogTimePicker(
                    label: "Start prompts",
                    hour: $workLogStartHour,
                    minute: $workLogStartMinute
                )
                .disabled(!workLogEnabled)
                .onChange(of: workLogStartHour) { _, _ in onWorkLogPreferenceChanged() }
                .onChange(of: workLogStartMinute) { _, _ in onWorkLogPreferenceChanged() }

                workLogTimePicker(
                    label: "End and review",
                    hour: $workLogEndHour,
                    minute: $workLogEndMinute
                )
                .disabled(!workLogEnabled)
                .onChange(of: workLogEndHour) { _, _ in onWorkLogPreferenceChanged() }
                .onChange(of: workLogEndMinute) { _, _ in onWorkLogPreferenceChanged() }
            } header: {
                Text("Daily Work Log")
            } footer: {
                Text("Loop opens a large writing window after each prompt. At the end time, you can read the day’s log. The day then stays read-only. Custom intervals start at 30 minutes so Loop can reliably schedule ahead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Open Loop")
                    Spacer()
                    Button {
                        if hotKeyRecorder.isRecording {
                            hotKeyRecorder.stopRecording()
                        } else {
                            hotKeyRecorder.startRecording { keyCode, modifiers in
                                hotKeyCode = Int(keyCode)
                                hotKeyModifierFlags = Int(modifiers.rawValue)
                                onHotKeyChanged()
                            }
                        }
                    } label: {
                        Text(hotKeyRecorder.isRecording ? "Press a key combination…" : hotKeyLabel)
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.bordered)
                    .tint(hotKeyRecorder.isRecording ? .accentColor : nil)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text("Click, then press a key combination with at least one modifier (⌘, ⌥, ⌃, or ⇧) to change it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Show My Data in Finder…") {
                    NSWorkspace.shared.activateFileViewerSelecting([dataFileURL])
                }
                Button(didCopyExport ? "Copied!" : "Copy All Reminders as Text") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(onExportRequested(), forType: .string)
                    didCopyExport = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        didCopyExport = false
                    }
                }
                Button("Export as Calendar (.ics)…", action: onICSExportRequested)
            } header: {
                Text("Your Data")
            } footer: {
                Text("Everything Loop knows lives in one plain JSON file on this Mac. Nothing is sent anywhere. Exporting as .ics lets your scheduled reminders show up in Calendar or another calendar app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Style", selection: $menuBarShowsText) {
                    Text("Icon").tag(false)
                    Text("Live Text").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: menuBarShowsText) { _, _ in
                    onMenuBarStyleChanged()
                }
            } header: {
                Text("Menu Bar")
            } footer: {
                Text(
                    menuBarShowsText
                        ? "Shows your next (or currently active) reminder as text, e.g. “Standup · in 12m.”"
                        : "Shows just the icon. A ring appears automatically while a scheduled block is active."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 10) {
                    ForEach(AccentColorOption.allCases) { option in
                        Button {
                            accentColorOptionRaw = option.rawValue
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(option.color ?? Color.accentColor)
                                    .frame(width: 22, height: 22)
                                if accentColorOptionRaw == option.rawValue {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(option.label)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Applies to Loop's own colors. Priority flags stay color-coded on their own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 14) {
                    if let icon = NSImage(named: "AppIcon") {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 48, height: 48)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loop")
                            .font(.headline)
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 700)
        .navigationTitle("Loop Preferences")
    }
}
