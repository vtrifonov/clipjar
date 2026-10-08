import CoreGraphics
import Testing
@testable import ClipjarCore

@Suite struct PanelPlacementTests {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    private func expectOrigin(_ frame: CGRect, _ x: CGFloat, _ y: CGFloat, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(frame.minX - x) < 0.01, "x \(frame.minX) != \(x)", sourceLocation: sourceLocation)
        #expect(abs(frame.minY - y) < 0.01, "y \(frame.minY) != \(y)", sourceLocation: sourceLocation)
        #expect(frame.size == PanelPlacement.size, sourceLocation: sourceLocation)
    }

    @Test func statusItem() {
        let button = CGRect(x: 700, y: 878, width: 24, height: 22)
        expectOrigin(PanelPlacement.belowStatusItem(buttonFrame: button, visibleFrame: visible), 352, 407)
    }

    @Test func statusItemBelowButtonWhenRoomAllows() {
        let button = CGRect(x: 700, y: 700, width: 24, height: 22)
        expectOrigin(PanelPlacement.belowStatusItem(buttonFrame: button, visibleFrame: visible), 352, 234)
    }

    @Test func cursorBelow() {
        expectOrigin(PanelPlacement.nearCursor(CGPoint(x: 720, y: 600), visibleFrame: visible), 360, 124)
    }

    @Test func cursorFlipsAbove() {
        expectOrigin(PanelPlacement.nearCursor(CGPoint(x: 720, y: 300), visibleFrame: visible), 360, 316)
    }

    @Test func flipThenClampTop() {
        expectOrigin(PanelPlacement.nearCursor(CGPoint(x: 720, y: 450), visibleFrame: visible), 360, 407)
    }

    @Test func clampLeft() {
        #expect(PanelPlacement.nearCursor(CGPoint(x: 100, y: 600), visibleFrame: visible).minX == 8)
    }

    @Test func clampRight() {
        #expect(PanelPlacement.nearCursor(CGPoint(x: 1400, y: 600), visibleFrame: visible).minX == 712)
    }

    @Test func centred() {
        expectOrigin(PanelPlacement.centred(visibleFrame: visible), 360, 276.67)
    }

    @Test func negativeOriginScreen() {
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        expectOrigin(PanelPlacement.nearCursor(CGPoint(x: -960, y: 500), visibleFrame: screen), -1320, 24)
    }

    @Test func panelLargerThanScreen() {
        let small = CGRect(x: 0, y: 0, width: 600, height: 400)
        let frames = [
            PanelPlacement.centred(visibleFrame: small),
            PanelPlacement.nearCursor(CGPoint(x: 300, y: 200), visibleFrame: small),
            PanelPlacement.belowStatusItem(buttonFrame: CGRect(x: 500, y: 402, width: 24, height: 22), visibleFrame: small),
        ]
        for frame in frames {
            #expect(frame.minX == 8)
            #expect(frame.maxY == 392)
        }
    }
}
