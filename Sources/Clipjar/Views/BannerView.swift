import AppKit
import ClipjarCore
import SwiftUI

/// A warning under the header (at most two lines), with the action that resolves it.
struct BannerView: View {
    let banner: Banner
    let onDismiss: () -> Void
    /// Closes the panel before an action brings another app forward.
    let onLeave: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(message)
            Spacer(minLength: 4)
            action
            if banner.isDismissible {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.yellow.opacity(0.15)))
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        switch banner {
        case .accessibility:
            "Allow Accessibility access so Clipjar can paste for you. Until then, ⏎ copies."
        case .recoveredFromCorruption:
            "Your clip history was damaged and has been reset. The old file was kept in the Clipjar support folder."
        case .storageUnavailable:
            "History can't be saved to disk this session."
        case .storageError:
            "Couldn't save the last clip."
        case .storageCorrupt:
            "Clipjar's history database is damaged. Restart Clipjar to repair."
        case .pasteboardDenied:
            "Clipjar can't read your clipboard. Allow it in System Settings ▸ Privacy & Security."
        case .appTranslocated:
            "Move Clipjar to the Applications folder so permissions stick."
        }
    }

    @ViewBuilder private var action: some View {
        switch banner {
        case .accessibility:
            Button("Open Settings") {
                onLeave()
                SystemSettingsLinks.openAccessibility()
                BannerActions.promptForAccessibilityOnce()
            }
            .controlSize(.small)
        case .pasteboardDenied:
            Button("Open Settings") {
                onLeave()
                SystemSettingsLinks.open(SystemSettingsLinks.privacy)
            }
            .controlSize(.small)
        case .recoveredFromCorruption:
            Button("Show in Finder") {
                onLeave()
                guard let dir = try? StoreOpener.defaultSupportDirectory() else { return }
                NSWorkspace.shared.activateFileViewerSelecting([dir])
            }
            .controlSize(.small)
        case .storageUnavailable, .storageError, .storageCorrupt, .appTranslocated:
            EmptyView()
        }
    }
}

/// System Settings deep links.
enum SystemSettingsLinks {
    static let accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    static let privacy = "x-apple.systempreferences:com.apple.preference.security"

    static func openAccessibility() {
        open(accessibility)
    }

    static func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum BannerActions {
    private static var prompted = false

    /// The system trust prompt, at most once per launch.
    static func promptForAccessibilityOnce() {
        guard !prompted else { return }
        prompted = true
        SystemAccessibility().promptForTrust()
    }
}
