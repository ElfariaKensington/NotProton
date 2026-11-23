// Drives the cursor to the top and bottom screen edges with HID events and reports
// which window is visible at each edge (front-most on-screen window under the point),
// plus a screenshot of each hit. usage: probe <label>
import AppKit

let label = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "probe"
let dir = FileManager.default.currentDirectoryPath
let f = NSScreen.main!.frame, W = f.width, H = f.height

func move(_ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func windows() -> [[String: Any]] {
    (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
}
func describe(_ w: [String: Any]) -> String {
    let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    return "\(w[kCGWindowOwnerName as String] ?? "?")/\(w[kCGWindowName as String] ?? "")"
        + " pid=\(w[kCGWindowOwnerPID as String] ?? 0) layer=\(w[kCGWindowLayer as String] ?? 0)"
        + " bounds=\(Int(b["X"] ?? 0)),\(Int(b["Y"] ?? 0)) \(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0))"
}
// Front-most visible window under a point, skipping the cursor and invisible overlays.
func topWindow(at p: CGPoint) -> String {
    for w in windows() {
        guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
              (w[kCGWindowLayer as String] as? Int ?? 0) < 1000 else { continue }
        let r = CGRect(x: b["X"]!, y: b["Y"]!, width: b["Width"]!, height: b["Height"]!)
        if r.width > 1 && r.height > 1 && r.contains(p) { return describe(w) }
    }
    return "none"
}
func shot(_ name: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-t", "jpg", "\(dir)/\(label)-\(name).jpg"]
    try? p.run(); p.waitUntilExit()
}
func hit(_ name: String, y: CGFloat, probeY: CGFloat, steps: Int) {
    move(CGPoint(x: W / 2, y: H / 2)); usleep(600_000)
    let before = topWindow(at: CGPoint(x: W / 2, y: probeY))
    for i in 0..<steps { move(CGPoint(x: W / 2 + CGFloat(i % 3), y: y)); usleep(50_000) }
    let during = topWindow(at: CGPoint(x: W / 2, y: probeY))
    let dock = windows().contains { ($0[kCGWindowOwnerName as String] as? String) == "Dock" && ($0[kCGWindowLayer as String] as? Int) == 20 }
    shot(name)
    print("\(label) \(name): before=[\(before)] during=[\(during)] dockWindowOnScreen=\(dock)")
}
print("\(label) front=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") pid=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) screen=\(Int(W))x\(Int(H))")
hit("top", y: 0, probeY: 4, steps: 30)
hit("bottom", y: H - 1, probeY: H - 30, steps: 40)
move(CGPoint(x: W / 2, y: H / 2))
