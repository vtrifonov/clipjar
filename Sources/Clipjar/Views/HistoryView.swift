import AppKit
import ClipjarCore
import SwiftUI

/// The whole panel: search header, banners, filter chips, list and preview, footer hints.
struct HistoryView: View {
    let model: HistoryViewModel
    let settings: SettingsStore

    @FocusState private var searchFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !model.banners.isEmpty {
                VStack(spacing: 6) {
                    ForEach(model.banners, id: \.self) { banner in
                        BannerView(
                            banner: banner,
                            onDismiss: { model.dismiss(banner) },
                            onLeave: { model.handle(.close) }
                        )
                    }
                }
                .padding(.top, 8)
            }
            FilterBar(model: model)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if settings.isPaused {
                Divider()
                PausedBar(pausedUntil: settings.pausedUntil) { settings.resume() }
            }
            Divider()
            footer
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast) { model.handle(.undoDelete) }
                    .padding(.bottom, 28 + 12)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.toast)
        .frame(
            minWidth: PanelPlacement.minSize.width, maxWidth: .infinity,
            minHeight: PanelPlacement.minSize.height, maxHeight: .infinity
        )
        .background(chrome)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(border, lineWidth: increasedContrast ? 1 : 0.5)
        )
        .onAppear { searchFocused = true }
        .onChange(of: model.openGeneration) { searchFocused = true }
    }

    // MARK: Chrome

    private var increasedContrast: Bool { contrast == .increased }

    @ViewBuilder private var chrome: some View {
        if increasedContrast {
            Color(nsColor: .windowBackgroundColor)
        } else {
            VisualEffectBackground()
        }
    }

    private var border: Color {
        increasedContrast ? Color(nsColor: .separatorColor) : Color.primary.opacity(0.08)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search clips", text: Bindable(model).query, prompt: Text("Search clips…"))
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .accessibilityLabel("Search clips")
                .padding(.leading, 8)
            if let hotkey = HotkeyController.currentShortcutDescription {
                Text(hotkey)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary))
                    .help("Opens and closes Clipjar")
                    .accessibilityLabel("Shortcut \(hotkey)")
                    .padding(.leading, 8)
            }
            Button {
                model.handle(.openSettings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
            .padding(.leading, 8)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    // MARK: Body

    @ViewBuilder private var content: some View {
        if model.isEmptyHistory {
            EmptyHistoryView(hotkey: HotkeyController.currentShortcutDescription)
        } else if model.isNoResults {
            NoResultsView(
                query: model.query,
                showSearchAll: model.filter != .all,
                onClear: { model.query = "" },
                onSearchAll: { model.filter = .all }
            )
        } else {
            HStack(spacing: 0) {
                ClipListView(model: model)
                Divider()
                PreviewView(model: model)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text(DisplayFormat.footerHints(
            pasteOnSelect: settings.pasteOnSelect,
            trusted: !model.banners.contains(.accessibility),
            selectedPinned: model.rows.first { $0.id == model.selectedID }?.isPinned ?? false
        ))
        .font(.caption)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}
