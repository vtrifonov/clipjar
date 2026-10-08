import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let editActions = ClipjarEditActions()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(editActions: editActions)
    }
}
