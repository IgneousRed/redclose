import AppKit

final class Probe: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var viewer: Process?
    var observer: NSObjectProtocol?
    let result = URL(fileURLWithPath: CommandLine.arguments[1])
    let viewerPath = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : ""
    var targetPID: pid_t? { CommandLine.arguments.count == 3 ? Int32(CommandLine.arguments[2].split(separator: ":")[0]) : nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.finish("FAIL: probe timed out") }
        if let targetPID {
            let window = makeWindow(x: 180)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
                let targetID = Int(CommandLine.arguments[2].split(separator: ":")[1])!
                let onscreen = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                let allHasWindow = all.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == targetID }
                let onscreenHasWindow = onscreen.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == targetID }
                let otherSpaceWindow = allHasWindow && !onscreenHasWindow
                let count = serverWindowCount(pid: targetPID)
                let passed = otherSpaceWindow && (count ?? 0) > 0
                self.finish(passed ? "PASS: full-screen window on another Space is counted (\(count!))"
                    : "FAIL: could not verify other-Space full-screen window; offscreen=\(otherSpaceWindow), count=\(String(describing: count))")
            }
            return
        }
        let first = makeWindow(x: 120)
        let second = makeWindow(x: 480)
        first.orderBack(nil)
        second.orderBack(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard (serverWindowCount(pid: getpid()) ?? 0) >= 2 else { self.finish("FAIL: two ordinary windows not counted"); return }
            print("PASS: two ordinary windows counted")
            first.close()
            second.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard serverWindowCount(pid: getpid()) == 0 else { self.finish("FAIL: closed ordinary windows are still counted"); return }
                print("PASS: no ordinary windows remaining reports zero")
                second.makeKeyAndOrderFront(nil)
                second.miniaturize(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    guard second.isMiniaturized else { self.finish("FAIL: could not minimize test window"); return }
                    print("PASS: test window can be minimized")
                    second.deminiaturize(nil)
                    self.observer = NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification,
                        object: second, queue: .main) { _ in self.checkOtherSpace() }
                    second.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    second.toggleFullScreen(nil)
                }
            }
        }
    }

    func makeWindow(x: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: x, y: 200, width: 300, height: 180),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "RedClose temporary window check"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = .fullScreenPrimary
        windows.append(window)
        return window
    }

    func checkOtherSpace() {
        guard (serverWindowCount(pid: getpid()) ?? 0) > 0 else { finish("FAIL: full-screen window not counted"); return }
        print("PASS: full-screen window counted")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: viewerPath)
        process.arguments = [result.path, "\(getpid()):\(windows[1].windowNumber)"]
        viewer = process
        do { try process.run() } catch { finish("FAIL: observer launch: \(error)"); return }
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
            if let text = try? String(contentsOf: self.result, encoding: .utf8) {
                timer.invalidate()
                guard text.hasPrefix("PASS:") else { self.finish(text); return }
                print(text)
                self.windows[1].close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let count = serverWindowCount(pid: getpid())
                    self.finish(count == 0 ? "PASS: closing the last full-screen window reports zero"
                        : "FAIL: after closing full-screen window, count=\(String(describing: count))")
                }
            }
        }
    }

    func finish(_ text: String) {
        if targetPID != nil { try? text.write(to: result, atomically: true, encoding: .utf8) }
        print(text)
        fflush(stdout)
        exit(text.hasPrefix("PASS:") ? 0 : 1)
    }
}

@main
enum ProbeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = Probe()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}
