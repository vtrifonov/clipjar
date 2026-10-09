import CoreGraphics

/// Panel frames in AppKit screen coordinates (origin bottom-left, y up), always clamped into the
/// visible frame inset by `inset`.
public enum PanelPlacement {
    public static let size = CGSize(width: 720, height: 460)
    public static let minSize = CGSize(width: 560, height: 340)
    public static let inset: CGFloat = 8

    /// The stored size (or the default), at least `minSize` and no larger than the inset visible frame.
    public static func fittedSize(_ stored: CGSize?, visibleFrame: CGRect) -> CGSize {
        let preferred = stored ?? size
        let area = visibleFrame.insetBy(dx: inset, dy: inset)
        return CGSize(
            width: max(minSize.width, min(preferred.width, area.width)),
            height: max(minSize.height, min(preferred.height, area.height))
        )
    }

    /// Centred under the status item button, top edge 6 pt below it.
    public static func belowStatusItem(buttonFrame: CGRect, visibleFrame: CGRect, size: CGSize = size) -> CGRect {
        let top = buttonFrame.minY - 6
        let origin = CGPoint(x: buttonFrame.midX - size.width / 2, y: top - size.height)
        return clamp(CGRect(origin: origin, size: size), into: visibleFrame)
    }

    /// Top edge 16 pt below the cursor; flipped to 16 pt above it when it would run off the bottom.
    public static func nearCursor(_ p: CGPoint, visibleFrame: CGRect, size: CGSize = size) -> CGRect {
        var y = p.y - 16 - size.height
        if y < visibleFrame.minY + inset { y = p.y + 16 }
        return clamp(CGRect(x: p.x - size.width / 2, y: y, width: size.width, height: size.height), into: visibleFrame)
    }

    /// Horizontally centred, with a third of the free vertical space above it.
    public static func centred(visibleFrame: CGRect, size: CGSize = size) -> CGRect {
        let top = visibleFrame.maxY - (visibleFrame.height - size.height) / 3
        let origin = CGPoint(x: visibleFrame.midX - size.width / 2, y: top - size.height)
        return clamp(CGRect(origin: origin, size: size), into: visibleFrame)
    }

    /// A panel larger than the inset area is pinned to its left and top edges.
    private static func clamp(_ frame: CGRect, into visibleFrame: CGRect) -> CGRect {
        let area = visibleFrame.insetBy(dx: inset, dy: inset)
        var origin = frame.origin
        origin.x = frame.width > area.width ? area.minX : min(max(origin.x, area.minX), area.maxX - frame.width)
        origin.y = frame.height > area.height
            ? area.maxY - frame.height
            : min(max(origin.y, area.minY), area.maxY - frame.height)
        return CGRect(origin: origin, size: frame.size)
    }
}
