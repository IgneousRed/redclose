import AppKit

// Exercise a real close handler that hides its app and retains the NSWindow.
// No global input is synthesized, and no user application is closed.
final class HideProbe: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var progress: CloseProgress!
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        window = NSWindow(contentRect: CGRect(x: 120, y: 200, width: 300, height: 160),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "RedClose temporary hide check"
        window.isReleasedWhenClosed = false
        window.delegate = self
        // A real close click requires a visible window on the active Space. A
        // command-line fixture can otherwise inherit a different Space, correctly
        // making the conservative server query refuse its hidden-window quit.
        window.collectionBehavior = .moveToActiveSpace
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let onscreen = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            let visible = onscreen.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == self.window.windowNumber }
            guard visible, !NSRunningApplication.current.isHidden, serverWindowCount(pid: getpid()) == 1 else {
                self.finish("FAIL: expected one onscreen, unhidden native window", passed: false)
            }
            self.progress = CloseProgress(started: ProcessInfo.processInfo.systemUptime, hiddenCloseAllowed: true)
            self.window.performClose(nil)
            self.timer = Timer.scheduledTimer(withTimeInterval: Timing.poll, repeats: true) { _ in self.check() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.finish("FAIL: hide check timed out", passed: false) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }

    func check() {
        let hidden = NSRunningApplication.current.isHidden
        let retained = NSApp.windows.contains(window)
        let count = serverWindowCount(pid: getpid())
        let decision = progress.check(now: ProcessInfo.processInfo.systemUptime, originalOpen: retained,
                                      windowCount: retained ? 1 : 0, dialogOpen: false,
                                      serverCount: count, appHidden: hidden)
        switch decision {
        case .wait: break
        case .stop: finish("FAIL: hidden=\(hidden), retained=\(retained), serverCount=\(String(describing: count))", passed: false)
        case .quit:
            guard hidden, retained, !window.isVisible, count == 0 else {
                finish("FAIL: expected a retained but hidden window", passed: false)
            }
            finish("PASS: native close-to-hide retains the window; hidden state and server query permit a confirmed quit", passed: true)
        }
    }

    func finish(_ message: String, passed: Bool) -> Never {
        print(message)
        fflush(stdout)
        exit(passed ? 0 : 1)
    }
}

@main
enum HideProbeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = HideProbe()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}
