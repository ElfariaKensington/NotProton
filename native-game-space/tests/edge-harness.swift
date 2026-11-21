// Edge-hit harness: native fullscreen window, HideDock|HideMenuBar requested,
// cursor driven to the top and bottom edges with real HID events, screen strips
// compared before/after to detect a revealed menu bar or Dock.
// usage: swiftc -O edge-harness.swift -o edge-harness && ./edge-harness MODE
//   plain            regular app, default fullscreen options (control: both appear)
//   regular          regular app, HideDock|HideMenuBar
//   accessory        accessory app, HideDock|HideMenuBar
//   promote          accessory, transformed to foreground once in the Space
//   regular-level    regular, HideDock|HideMenuBar, window at NSStatusWindowLevel + 1
//   plain-acc-level  accessory, default options, raised level
//   border-reg|border-acc  borderless desktop window, HideDock|HideMenuBar
// Needs Accessibility (cursor events) and Screen Recording (edge pixels).
import AppKit
import ApplicationServices

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "regular"
let out = FileManager.default.currentDirectoryPath
func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions o: NSApplication.PresentationOptions = []) -> NSApplication.PresentationOptions {
        return mode.hasPrefix("plain") ? o : [.fullScreen, .hideDock, .hideMenuBar]
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 800, height: 500),
                          styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if mode.hasPrefix("border") {
            window.styleMask = [.borderless]
            window.setFrame(NSScreen.main!.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            after(1.5) { self.run() }
        } else {
            after(1.0) { self.window.toggleFullScreen(nil) }
        }
    }
    func windowDidEnterFullScreen(_ n: Notification) {
        after(1.5) { self.run() }
    }
    func transform(_ state: ProcessApplicationTransformState) {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        let st = TransformProcessType(&psn, state)
        log("transform \(state) -> \(st) policy=\(NSApp.activationPolicy().rawValue)")
    }
    func run() {
        if mode == "promote" {
            transform(ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
            NSApp.presentationOptions = [.fullScreen, .hideDock, .hideMenuBar]
        } else if mode.hasPrefix("border") {
            NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        } else if !mode.hasPrefix("plain") {
            NSApp.presentationOptions = [.fullScreen, .hideDock, .hideMenuBar]
        }
        if mode.hasSuffix("level") { window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) }
        after(1.0) { self.probe() }
    }
    func probe() {
        log("mode=\(mode) active=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue) requested=0x\(String(NSApp.presentationOptions.rawValue, radix: 16)) system=0x\(String(NSApp.currentSystemPresentationOptions.rawValue, radix: 16))")
        let f = NSScreen.main!.frame  // points, global top-left == (0,0) for main screen in CG
        let w = f.width, h = f.height
        // Park the cursor in the centre, take reference strips.
        move(CGPoint(x: w / 2, y: h / 2)); usleep(400_000)
        let topRef = strip(y: 0, h: 40, w: w, name: "top0"), botRef = strip(y: h - 90, h: 90, w: w, name: "bot0")
        // Top edge: hold at y=0 for 1.5 s.
        for i in 0..<30 { move(CGPoint(x: w / 2 + CGFloat(i % 3), y: 0)); usleep(50_000) }
        let topHit = strip(y: 0, h: 40, w: w, name: "top1")
        let menuWin = onscreen().filter { ($0[kCGWindowName as String] as? String) == "Menubar" }.count
        move(CGPoint(x: w / 2, y: h / 2)); usleep(1_200_000)
        // Bottom edge: push against y=h-1 for 2 s.
        for i in 0..<40 { move(CGPoint(x: w / 2 + CGFloat(i % 3), y: h - 1)); usleep(50_000) }
        let botHit = strip(y: h - 90, h: 90, w: w, name: "bot1")
        let dockWin = onscreen().filter { ($0[kCGWindowOwnerName as String] as? String) == "Dock" && ($0[kCGWindowLayer as String] as? Int) == 20 }.count
        move(CGPoint(x: w / 2, y: h / 2)); usleep(800_000)
        let dTop = diff(topRef, topHit), dBot = diff(botRef, botHit)
        log(String(format: "RESULT mode=%@ topDiff=%.4f botDiff=%.4f menubarWindowsOnTopHit=%d dockWindowsOnBottomHit=%d => menu=%@ dock=%@",
                   mode, dTop, dBot, menuWin, dockWin, dTop > 0.02 ? "SHOWN" : "hidden", dBot > 0.02 ? "SHOWN" : "hidden"))
        if mode == "promote" { transform(ProcessApplicationTransformState(kProcessTransformToUIElementApplication)) }
        if !mode.hasPrefix("border") { window.toggleFullScreen(nil) }
        after(2.0) { NSApp.terminate(nil) }
    }
}

func after(_ s: Double, _ b: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: b) }
func move(_ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
func onscreen() -> [[String: Any]] {
    (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
}
func strip(y: CGFloat, h: CGFloat, w: CGFloat, name: String) -> CGImage? {
    let path = "\(out)/\(mode)-\(name).png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-R", "0,\(Int(y)),\(Int(w)),\(Int(h))", path]
    try? p.run(); p.waitUntilExit()
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
func pixels(_ i: CGImage) -> [UInt8] {
    var buf = [UInt8](repeating: 0, count: i.width * i.height * 4)
    let ctx = CGContext(data: &buf, width: i.width, height: i.height, bitsPerComponent: 8, bytesPerRow: i.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(i, in: CGRect(x: 0, y: 0, width: i.width, height: i.height))
    return buf
}
// Fraction of pixels whose colour changed noticeably.
func diff(_ a: CGImage?, _ b: CGImage?) -> Double {
    guard let a = a, let b = b, a.width == b.width, a.height == b.height else { return -1 }
    let pa = pixels(a), pb = pixels(b)
    var changed = 0
    for i in stride(from: 0, to: pa.count, by: 4) {
        let d = abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1])) + abs(Int(pa[i + 2]) - Int(pb[i + 2]))
        if d > 60 { changed += 1 }
    }
    return Double(changed) / Double(pa.count / 4)
}

let app = NSApplication.shared
app.setActivationPolicy(mode.contains("acc") ? .accessory : .regular)
let d = Delegate()
app.delegate = d
app.run()
