import AppKit
import ClipjarCore
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let settings: SettingsStore
    let store: ClipStore
    let retention: RetentionChanger

    var body: some View {
        Form {
            GeneralSection(settings: settings)
            HistorySection(settings: settings, store: store, retention: retention)
            PrivacySection(settings: settings)
            Section {
                Text(Self.versionLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .keyboardShortcutsConflictPolicy(.init(menuItem: .block, systemShortcut: .block))
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String,
              let build = info?["CFBundleVersion"] as? String
        else { return "Clipjar dev" }
        return "Clipjar \(version) (\(build))"
    }
}

/// Secondary explanatory line under a control.
private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: General

private struct GeneralSection: View {
    @Bindable var settings: SettingsStore

    @State private var trusted = AXIsProcessTrusted()
    @State private var launchAtLogin = false
    @State private var loginStatus: SMAppService.Status = .notRegistered
    @State private var loginError: String?

    var body: some View {
        Section("General") {
            VStack(alignment: .leading, spacing: 4) {
                KeyboardShortcuts.Recorder("Open Clipjar:", name: .togglePanel)
                    .shortcutValidation { shortcut in
                        shortcut.modifiers.isDisjoint(with: [.command, .option, .control])
                            ? .disallow(reason: "Use at least one of ⌘, ⌥ or ⌃.")
                            : .allow
                    }
                Caption("Clear to use the menu bar icon only.")
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Paste automatically after selecting", isOn: $settings.pasteOnSelect)
                if trusted {
                    Caption("Accessibility: Allowed ✓")
                } else {
                    HStack(spacing: 4) {
                        Caption("Accessibility: Not allowed —")
                        Button("Open Settings") { SystemSettingsLinks.openAccessibility() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Caption(loginError)
                } else if loginStatus == .requiresApproval {
                    HStack(spacing: 4) {
                        Caption("Needs your approval in Login Items.")
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        trusted = AXIsProcessTrusted()
        loginStatus = SMAppService.mainApp.status
        launchAtLogin = loginStatus == .enabled
    }

    private func setLaunchAtLogin(_ on: Bool) {
        launchAtLogin = on
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
            loginStatus = SMAppService.mainApp.status
        } catch {
            launchAtLogin = !on
            loginError = error.localizedDescription
        }
    }
}

// MARK: History

private struct HistorySection: View {
    let settings: SettingsStore
    let store: ClipStore
    let retention: RetentionChanger

    private struct Pending {
        let removing: Int
        let limit: HistoryLimit
        let maxAgeDays: Int
    }

    @State private var limit: HistoryLimit = .l1000
    @State private var maxAgeDays = 0
    @State private var pending: Pending?
    @State private var confirmingClear = false

    private static let limits: [(HistoryLimit, String)] = [
        (.l200, "200 clips"), (.l1000, "1,000 clips"), (.l5000, "5,000 clips"), (.l10000, "10,000 clips"),
        (.unlimited, "Unlimited"),
    ]
    private static let ages: [(Int, String)] = [
        (0, "Never"), (1, "1 day"), (7, "1 week"), (30, "30 days"), (90, "90 days"), (365, "1 year"),
    ]

    var body: some View {
        Section("History") {
            Picker("Keep", selection: $limit) {
                ForEach(Self.limits, id: \.0) { Text($0.1).tag($0.0) }
            }
            Picker("Remove clips older than", selection: $maxAgeDays) {
                ForEach(Self.ages, id: \.0) { Text($0.1).tag($0.0) }
            }
            Caption("Pinned clips are never removed.")
            HStack {
                Spacer()
                Button("Clear History…", role: .destructive) { confirmingClear = true }
            }
        }
        .onAppear {
            limit = settings.historyLimit
            maxAgeDays = settings.maxAgeDays
        }
        .onChange(of: limit) { propose() }
        .onChange(of: maxAgeDays) { propose() }
        .confirmationDialog(
            "Remove \((pending?.removing ?? 0).formatted()) older clips? Pinned clips are kept.",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { cancelPending() } })
        ) {
            Button("Remove", role: .destructive) { applyPending() }
            Button("Cancel", role: .cancel) { cancelPending() }
        }
        .confirmationDialog("Clear all unpinned clips? This can't be undone.", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { clearHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func propose() {
        let limit = limit
        let maxAgeDays = maxAgeDays
        guard limit != settings.historyLimit || maxAgeDays != settings.maxAgeDays else { return }
        Task {
            do {
                switch try await retention.propose(limit: limit, maxAgeDays: maxAgeDays) {
                case .applied: break
                case let .needsConfirmation(n): pending = Pending(removing: n, limit: limit, maxAgeDays: maxAgeDays)
                }
            } catch {
                logFailure("retention change failed", error)
                revert()
            }
        }
    }

    private func applyPending() {
        guard let p = pending else { return }
        pending = nil
        Task {
            do {
                try await retention.apply(limit: p.limit, maxAgeDays: p.maxAgeDays)
            } catch {
                logFailure("retention apply failed", error)
                revert()
            }
        }
    }

    /// The dialog's binding also lands here after Remove, when nothing is pending any more.
    private func cancelPending() {
        guard pending != nil else { return }
        pending = nil
        revert()
    }

    private func revert() {
        limit = settings.historyLimit
        maxAgeDays = settings.maxAgeDays
    }

    private func clearHistory() {
        let store = store
        Task {
            do {
                _ = try await store.clearAll(keepPinned: true)
            } catch {
                logFailure("clear history failed", error)
            }
        }
    }

    private func logFailure(_ message: StaticString, _ error: any Error) {
        let e = error as NSError
        Log.store.error("\(message, privacy: .public): \(e.domain, privacy: .public) \(e.code, privacy: .public)")
    }
}

// MARK: Privacy

private struct PrivacySection: View {
    let settings: SettingsStore
    @State private var selection: String?

    var body: some View {
        Section("Privacy") {
            Toggle("Pause capture", isOn: Binding(
                get: { settings.isPaused },
                set: { $0 ? settings.pause(for: nil) : settings.resume() }
            ))
            HStack {
                Spacer()
                Button("Pause for 15 minutes") { settings.pause(for: 900) }
            }
        }

        Section {
            if settings.ignoredBundleIDs.isEmpty {
                Text("No ignored apps")
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.ignoredBundleIDs, id: \.self) { id in
                IgnoredAppRow(bundleID: id, isSelected: selection == id)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = selection == id ? nil : id }
            }
            HStack(spacing: 0) {
                Button(action: addApps) {
                    Image(systemName: "plus").frame(width: 22, height: 18)
                }
                .help("Add apps to ignore")
                .accessibilityLabel("Add app")
                Divider().frame(height: 14)
                Button(action: removeSelected) {
                    Image(systemName: "minus").frame(width: 22, height: 18)
                }
                .disabled(selection == nil)
                .help("Stop ignoring the selected app")
                .accessibilityLabel("Remove selected app")
                Spacer()
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Ignored apps")
        } footer: {
            Caption("Clipjar also skips anything apps mark as concealed, such as passwords. History is stored unencrypted on this Mac and never leaves it.")
        }
    }

    private func removeSelected() {
        guard let selection else { return }
        settings.ignoredBundleIDs.removeAll { $0 == selection }
        self.selection = nil
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK else { return }
        var ids = settings.ignoredBundleIDs
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !ids.contains(id) else { continue }
            ids.append(id)
        }
        settings.ignoredBundleIDs = ids
    }
}

private struct IgnoredAppRow: View {
    let bundleID: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let icon = ImageCache.shared.appIcon(bundleID: bundleID) {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(displayName)
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : .clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var displayName: String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
