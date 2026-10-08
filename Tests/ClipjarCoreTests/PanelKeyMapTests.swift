import AppKit
import Testing
@testable import ClipjarCore

@Suite struct PanelKeyMapTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let toast: Bool
        let expected: PanelCommand?
        var testDescription: String { "key \(keyCode) mods \(modifiers.rawValue) toast \(toast)" }

        init(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags, _ toast: Bool, _ expected: PanelCommand?) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.toast = toast
            self.expected = expected
        }

        init(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags, _ expected: PanelCommand?) {
            self.init(keyCode, modifiers, false, expected)
        }
    }

    static let digitCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    static let cases: [Case] = [
        Case(126, [], .moveUp),
        Case(125, [], .moveDown),
        Case(126, [.command], .moveToTop),
        Case(125, [.command], .moveToBottom),
        Case(126, [.numericPad, .function], .moveUp),
        Case(116, [], .pageUp),
        Case(121, [], .pageDown),
        Case(36, [], .activate(copyOnly: false)),
        Case(76, [], .activate(copyOnly: false)),
        Case(36, [.option], .activate(copyOnly: true)),
        Case(76, [.option], .activate(copyOnly: true)),
        Case(18, [.command, .option], nil),
        Case(35, [.command], .togglePin),
        Case(51, [.command], .delete),
        Case(6, [.command], true, .undoDelete),
        Case(6, [.command], false, nil),
        Case(48, [], .nextFilter),
        Case(48, [.shift], .previousFilter),
        Case(53, [], .escape),
        Case(43, [.command], .openSettings),
        Case(13, [.command], .close),
        Case(12, [.command], .close),
        Case(0, [.command], nil),
        Case(8, [.command], nil),
        Case(9, [.command], nil),
        Case(7, [.command], nil),
        Case(0, [], nil),
        Case(126, [.shift], nil),
        Case(126, [.capsLock], .moveUp),
    ] + digitCodes.enumerated().map { Case($1, [.command], .activateRow($0 + 1)) }

    @Test(arguments: cases)
    func maps(_ c: Case) {
        #expect(PanelKeyMap.command(for: c.keyCode, modifiers: c.modifiers, deleteToastVisible: c.toast) == c.expected)
    }
}
