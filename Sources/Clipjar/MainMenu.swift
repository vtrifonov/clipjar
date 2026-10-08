import AppKit
import ClipjarCore

/// Never visible for an accessory app; it exists so key equivalents (⌘A/⌘C/⌘V/⌘X/⌘Z, ⌘, ⌘W ⌘Q) reach
/// text fields and the app.
enum MainMenu {
    static func build(editActions: ClipjarEditActions) -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "Clipjar")
        appMenu.addItem(
            withTitle: "About Clipjar",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(withTitle: "Settings…", action: Selector(("openSettings:")), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Clipjar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(ClipjarEditActions.clipjarCut(_:)), keyEquivalent: "x")
            .target = editActions
        edit.addItem(withTitle: "Copy", action: #selector(ClipjarEditActions.clipjarCopy(_:)), keyEquivalent: "c")
            .target = editActions
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(window, to: main)

        return main
    }

    private static func add(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}

/// Copy and cut routed through the responder chain, then marked as Clipjar's own write so text copied
/// inside Clipjar is never captured.
final class ClipjarEditActions: NSObject {
    @objc func clipjarCopy(_ sender: Any?) {
        forward(#selector(NSText.copy(_:)), from: sender)
    }

    @objc func clipjarCut(_ sender: Any?) {
        forward(#selector(NSText.cut(_:)), from: sender)
    }

    private func forward(_ action: Selector, from sender: Any?) {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        NSApp.sendAction(action, to: nil, from: sender)
        if pasteboard.changeCount != before {
            pasteboard.pasteboardItems?.first?.setData(Data(), forType: .init(PasteboardTypes.marker))
        }
    }
}
