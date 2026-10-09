import AppKit
import SwiftUI

/// Bottom-right corner handle. A borderless panel only resizes from a few points at its edges, which is
/// hard to hit, so this gives a visible, generous target. Grows to the right and down, like a window corner.
struct ResizeGrip: NSViewRepresentable {
    /// Called with the panel size when a drag ends.
    let onEnd: (CGSize) -> Void

    func makeNSView(context: Context) -> GripView {
        let view = GripView()
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: GripView, context: Context) {
        view.onEnd = onEnd
    }

    final class GripView: NSView {
        var onEnd: ((CGSize) -> Void)?
        private var start: (mouse: NSPoint, frame: NSRect)?

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: Self.cursor)
        }

        private static var cursor: NSCursor {
            if #available(macOS 15, *) {
                return .frameResize(position: .bottomRight, directions: .all)
            }
            return .crosshair
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            start = (NSEvent.mouseLocation, window.frame)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let start else { return }
            let mouse = NSEvent.mouseLocation
            let minSize = window.contentMinSize
            let width = max(minSize.width, start.frame.width + mouse.x - start.mouse.x)
            let height = max(minSize.height, start.frame.height - (mouse.y - start.mouse.y))
            window.setFrame(
                NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height),
                display: true
            )
        }

        override func mouseUp(with event: NSEvent) {
            guard start != nil, let window else { return }
            start = nil
            onEnd?(window.frame.size)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.tertiaryLabelColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            path.lineCapStyle = .round
            // Three diagonal strokes tucked into the corner (y grows upwards).
            let corner = NSPoint(x: bounds.maxX - 3, y: bounds.minY + 3)
            for length in [4.0, 8.0, 12.0] {
                path.move(to: NSPoint(x: corner.x - length, y: corner.y))
                path.line(to: NSPoint(x: corner.x, y: corner.y + length))
            }
            path.stroke()
        }
    }
}
