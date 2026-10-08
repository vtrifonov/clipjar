import ClipjarCore
import SwiftUI

/// Floating confirmation above the footer.
struct ToastView: View {
    let toast: Toast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            switch toast {
            case .deleted:
                Text("Clip deleted ·")
                Button("Undo ⌘Z", action: onUndo)
                    .buttonStyle(.borderless)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
            case .confirmPinnedDelete:
                Text("Pinned — press ⌘⌫ again to delete")
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .onAppear { AccessibilityNotification.Announcement(announcement).post() }
    }

    private var announcement: String {
        switch toast {
        case .deleted: "Clip deleted. Press Command Z to undo."
        case .confirmPinnedDelete: "Pinned. Press Command Delete again to delete."
        }
    }
}

struct EmptyHistoryView: View {
    let hotkey: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text("Your clipboard history is empty")
                .font(.title3.weight(.medium))
            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 360)
        .accessibilityElement(children: .combine)
    }

    private var hint: String {
        if let hotkey { return "Copy something, then press \(hotkey) to find it here." }
        return "Copy something, then click the Clipjar icon in the menu bar."
    }
}

struct NoResultsView: View {
    let query: String
    let showSearchAll: Bool
    let onClear: () -> Void
    let onSearchAll: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("No clips match “\(query)”")
                .font(.title3.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("Clear Search", action: onClear)
                if showSearchAll {
                    Button("Search All Types", action: onSearchAll)
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .frame(maxWidth: 420)
    }
}

/// Shown above the footer while capture is paused.
struct PausedBar: View {
    let pausedUntil: Date?
    let onResume: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "pause.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Resume", action: onResume)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        guard let pausedUntil else { return "Capture paused until you resume" }
        return "Capture paused · Resumes at \(pausedUntil.formatted(date: .omitted, time: .shortened))"
    }
}
