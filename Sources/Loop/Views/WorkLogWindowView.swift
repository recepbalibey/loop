import SwiftUI
import LoopKit

/// The deliberately large surface opened from a work-log notification. macOS owns the
/// banner size, but this window gives the actual writing task the visual weight it needs.
struct WorkLogWindowView: View {
    enum Mode {
        case write
        case review
    }

    let mode: Mode
    let onDismiss: () -> Void

    @Environment(WorkLogStore.self) private var workLogStore
    @State private var draft = ""

    private var todayEntries: [WorkLogEntry] {
        workLogStore.entries(for: .now)
    }

    private var isLocked: Bool {
        workLogStore.isLocked(on: .now)
    }

    private var title: String {
        mode == .review || isLocked ? "Today’s Work Log" : "What have you done so far?"
    }

    private var subtitle: String {
        if isLocked {
            return "This day is complete and read-only."
        }
        return todayEntries.isEmpty
            ? "Capture a clear, short update before you continue."
            : "Your update continues below the previous section."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isLocked ? "book.closed.fill" : "pencil.line")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.accentColor.opacity(0.16)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(28)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if todayEntries.isEmpty {
                        ContentUnavailableView(
                            "No updates yet",
                            systemImage: "note.text",
                            description: Text(isLocked ? "There were no notes recorded today." : "Write the first note below.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                    } else {
                        ForEach(todayEntries) { entry in
                            VStack(alignment: .leading, spacing: 9) {
                                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text(entry.text)
                                    .font(.body)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 20)

                            Divider()
                                .overlay(Color.accentColor.opacity(0.28))
                        }
                    }
                }
                .padding(.horizontal, 28)
            }

            if !isLocked {
                VStack(alignment: .leading, spacing: 10) {
                    Text(todayEntries.isEmpty ? "Your first update" : "Continue today’s log")
                        .font(.headline)
                    TextEditor(text: $draft)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 130, maxHeight: 190)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentColor.opacity(0.24)))
                }
                .padding(28)
                .background(.regularMaterial)
            }

            HStack {
                if isLocked {
                    Text("Read-only")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Each entry is saved locally on this Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                if !isLocked {
                    Button("Save Update") {
                        if workLogStore.append(draft) {
                            draft = ""
                            onDismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
