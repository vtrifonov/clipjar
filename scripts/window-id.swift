// Prints the window number of Clipjar's on-screen panel, for `screencapture -o -l <id>`.
// The status item is also a Clipjar window, so pick the largest one.
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []

func area(_ info: [String: Any]) -> Double {
    guard let bounds = info[kCGWindowBounds as String] as? [String: Double] else { return 0 }
    return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
}

let match = windows
    .filter { ($0[kCGWindowOwnerName as String] as? String) == "Clipjar" }
    .filter { (($0[kCGWindowLayer as String] as? Int) ?? 0) > 0 }
    .max { area($0) < area($1) }

guard let id = match?[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write(Data("No on-screen Clipjar window found.\n".utf8))
    exit(1)
}
print(id)
