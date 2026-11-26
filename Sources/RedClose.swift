import AppKit
import ApplicationServices
import Darwin

enum Timing {
    static let poll = 0.1
    static let confirmEmpty = 0.2
    static let cancelGrace = 1.0
    static let savePromptLimit = 300.0
    static let accessibilityTimeout: Float = 0.3
}

enum CloseDecision { case wait, stop, quit }

// Only a completed click creates this short-lived state. Nothing polls idle apps.
struct CloseProgress {
    let started: TimeInterval
    var hiddenCloseAllowed = false
    var hiddenSince: TimeInterval?
    var disappeared: TimeInterval?
    var empty: TimeInterval?

    mutating func check(now: TimeInterval, originalOpen: Bool, windowCount: Int,
                        dialogOpen: Bool, serverCount: Int?, appHidden: Bool = false) -> CloseDecision {
        guard now - started < Timing.savePromptLimit else { return .stop }
        // A save interaction breaks the link between this click and a later hide.
        if dialogOpen { hiddenCloseAllowed = false }
        if appHidden {
            guard hiddenCloseAllowed, !dialogOpen,
                  windowCount == (originalOpen ? 1 : 0), let serverCount else { return .stop }
            if serverCount > 0 {
                hiddenSince = nil
                return now - started < Timing.cancelGrace ? .wait : .stop
            }
            guard hiddenSince != nil || now - started < Timing.cancelGrace else { return .stop }
            if hiddenSince == nil { hiddenSince = now }
            return now - hiddenSince! >= Timing.confirmEmpty ? .quit : .wait
        }
        hiddenSince = nil
        if originalOpen {
            empty = nil
            disappeared = nil
            return dialogOpen || now - started < Timing.cancelGrace ? .wait : .stop
        }
        guard windowCount == 0, let serverCount else { return .stop }
        if disappeared == nil { disappeared = now }
        if serverCount > 0 {
            empty = nil
            // The closed window may briefly remain in the window server during animation.
            return now - disappeared! < Timing.cancelGrace ? .wait : .stop
        }
        if empty == nil { empty = now }
        return now - empty! >= Timing.confirmEmpty ? .quit : .wait
    }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, kAXPositionAttribute),
          let size = attribute(element, kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
          AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
          point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
          dimensions.width > 0, dimensions.height > 0 else { return nil }
    return CGRect(origin: point, size: dimensions)
}

// Public window lists also contain retained, closed windows. Space membership
// distinguishes these from real windows on another desktop or in full screen.
// Resolve the private API at runtime; if unavailable, refuse an uncertain quit.
struct SpaceReader {
    typealias Connection = @convention(c) () -> Int32
    typealias ActiveSpace = @convention(c) (Int32) -> UInt64
    typealias WindowSpaces = @convention(c) (Int32, Int32, CFArray) -> UnsafeRawPointer?
    let connection: Connection
    let activeSpace: ActiveSpace
    let windowSpaces: WindowSpaces

    static func load() -> SpaceReader? {
        // Keep the library loaded for the lifetime of these function pointers.
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connection = dlsym(library, "SLSMainConnectionID"),
              let active = dlsym(library, "SLSGetActiveSpace"),
              let spaces = dlsym(library, "SLSCopySpacesForWindows") else { return nil }
        return SpaceReader(connection: unsafeBitCast(connection, to: Connection.self),
                           activeSpace: unsafeBitCast(active, to: ActiveSpace.self),
                           windowSpaces: unsafeBitCast(spaces, to: WindowSpaces.self))
    }

    func spaces(of window: NSNumber) -> [NSNumber]? {
        guard let raw = windowSpaces(connection(), 0x7, [window] as CFArray) else { return nil }
        return Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue() as? [NSNumber]
    }
}

private let spaceReader = SpaceReader.load()
var spaceQueryAvailable: Bool { spaceReader != nil }

// .optionAll is deliberate: an offscreen/full-screen window must prevent quitting.
// Names and images aren't requested; no Screen Recording permission is needed.
func serverWindowCount(pid: pid_t) -> Int? {
    guard let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return nil }
    var count = 0
    for window in windows {
        guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber else { return nil }
        guard owner.int32Value == pid else { continue }
        guard let layer = window[kCGWindowLayer as String] as? NSNumber else { return nil }
        guard layer.intValue == 0 else { continue }
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let alpha = window[kCGWindowAlpha as String] as? NSNumber,
              rect.width.isFinite, rect.height.isFinite else { return nil }
        guard rect.width > 1, rect.height > 1, alpha.doubleValue > 0 else { continue }
        if window[kCGWindowIsOnscreen as String] as? Bool == true {
            count += 1
        } else {
            guard let reader = spaceReader,
                  let windowID = window[kCGWindowNumber as String] as? NSNumber,
                  let spaces = reader.spaces(of: windowID) else { return nil }
            let active = reader.activeSpace(reader.connection())
            if !spaces.isEmpty, !spaces.contains(where: { $0.uint64Value == active }) { count += 1 }
        }
    }
    return count
}

func eligible(_ app: NSRunningApplication) -> Bool {
    !app.isTerminated && app.activationPolicy == .regular
        && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        && app.bundleIdentifier != "com.apple.finder"
        && app.bundleURL != nil
        && !(app.bundleURL!.path.hasPrefix("/System/Library/"))
}

struct CloseClick {
    let app: NSRunningApplication
    let window: AXUIElement
    let buttonFrame: CGRect
    let hiddenCloseAllowed: Bool

    func acceptsRelease(at point: CGPoint) -> Bool { buttonFrame.contains(point) }
}

// Missing AX attributes are uncertainty, not permission to quit a retained window.
func isOrdinaryWindow(_ window: AXUIElement) -> Bool {
    guard attribute(window, kAXMinimizedAttribute) as? Bool == false,
          attribute(window, kAXModalAttribute) as? Bool == false,
          let children = attribute(window, kAXChildrenAttribute) as? [AXUIElement] else { return false }
    return children.allSatisfy {
        guard let role = attribute($0, kAXRoleAttribute) as? String else { return false }
        return role != kAXSheetRole
    }
}

struct PendingClose {
    let click: CloseClick
    var progress: CloseProgress
}

final class RedClose {
    var allowsApp: (String?) -> Bool = { _ in false }
    var onStatus: (() -> Void)?
    var onActivity: ((String) -> Void)?
    private(set) var hasPermission = false
    private(set) var isMonitoring = false
    private var enabled = false
    private var monitor: Any?
    private var localMonitor: Any?
    private var permissionTimer: Timer?
    private var closeTimer: Timer?
    private var click: CloseClick?
    private var pending: [pid_t: PendingClose] = [:]
    func start() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Timing.accessibilityTimeout)
        updatePermission()
        permissionTimer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.updatePermission() }
        RunLoop.main.add(permissionTimer!, forMode: .common)
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        cancelPending()
        updatePermission()
    }

    func cancelPending() {
        click = nil
        pending.removeAll()
        stopCloseTimerIfIdle()
    }

    private func updatePermission() {
        let previous = (hasPermission, isMonitoring)
        hasPermission = AXIsProcessTrusted()
        if hasPermission && enabled {
            if monitor == nil {
                monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp,
                    .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
                    self?.handle(event)
                }
                // Global monitors exclude this app. Its new UI must also revoke
                // hide inference on intervening input, without consuming events.
                localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown,
                    .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
                    self?.cancelHideInference()
                    return event
                }
                if monitor == nil || localMonitor == nil { removeMonitors() }
            }
        } else {
            removeMonitors()
            cancelPending()
        }
        isMonitoring = monitor != nil
        if previous.0 != hasPermission || previous.1 != isMonitoring { onStatus?() }
    }

    private func handle(_ event: NSEvent) {
        // A subsequent gesture could hide the app independently (e.g. Command-H).
        // Keep normal save/close handling alive, but revoke the hide inference.
        if event.type != .leftMouseUp { cancelHideInference() }
        guard event.type == .leftMouseDown || event.type == .leftMouseUp else { return }
        guard enabled, AXIsProcessTrusted(), let point = event.cgEvent?.location else { click = nil; return }
        if event.type == .leftMouseDown {
            click = nil
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
                  let hit else { return }
            var pid: pid_t = 0
            guard AXUIElementGetPid(hit, &pid) == .success,
                  let app = NSRunningApplication(processIdentifier: pid), eligible(app),
                  allowsApp(app.bundleIdentifier) else { return }
            let role = attribute(hit, kAXRoleAttribute) as? String
            let window = role == kAXWindowRole ? hit : elementAttribute(hit, kAXWindowAttribute)
            guard let window, let button = elementAttribute(window, kAXCloseButtonAttribute),
                  attribute(button, kAXEnabledAttribute) as? Bool == true,
                  let rect = frame(of: button), rect.contains(point) else { return }
            pending.removeValue(forKey: pid)
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, Timing.accessibilityTimeout)
            let windows = attribute(axApp, kAXWindowsAttribute) as? [AXUIElement]
            // Capture before mouse-up: hiding all windows must not erase evidence
            // of another window, including minimized or other-Space windows.
            let hiddenCloseAllowed = !app.isHidden && windows?.count == 1
                && windows!.contains { CFEqual($0, window) }
                && isOrdinaryWindow(window) && serverWindowCount(pid: pid) == 1
            click = CloseClick(app: app, window: window, buttonFrame: rect,
                               hiddenCloseAllowed: hiddenCloseAllowed)
        } else {
            let captured = click
            click = nil
            guard let captured, captured.acceptsRelease(at: point), eligible(captured.app),
                  allowsApp(captured.app.bundleIdentifier) else { return }
            pending[captured.app.processIdentifier] = PendingClose(
                click: captured, progress: CloseProgress(started: ProcessInfo.processInfo.systemUptime,
                    hiddenCloseAllowed: captured.hiddenCloseAllowed))
            onActivity?("Close click detected: \(captured.app.localizedName ?? "App").")
            if closeTimer == nil {
                closeTimer = Timer(timeInterval: Timing.poll, repeats: true) { [weak self] _ in self?.checkPending() }
                RunLoop.main.add(closeTimer!, forMode: .common)
            }
        }
    }

    private func checkPending() {
        for pid in Array(pending.keys) {
            guard var close = pending[pid] else { continue }
            let app = close.click.app
            guard enabled, AXIsProcessTrusted(), eligible(app), allowsApp(app.bundleIdentifier) else { pending.removeValue(forKey: pid); continue }
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, Timing.accessibilityTimeout)
            guard let windows = attribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else {
                onActivity?("\(app.localizedName ?? "App") kept running: window information unavailable.")
                pending.removeValue(forKey: pid)
                continue
            }
            let originalOpen = windows.contains { CFEqual($0, close.click.window) }
            let children = originalOpen ? attribute(close.click.window, kAXChildrenAttribute) as? [AXUIElement] ?? [] : []
            let dialogOpen = children.contains { attribute($0, kAXRoleAttribute) as? String == kAXSheetRole }
                || windows.contains { attribute($0, kAXModalAttribute) as? Bool == true }
            let hidden = app.isHidden
            if close.progress.hiddenCloseAllowed && originalOpen && !isOrdinaryWindow(close.click.window) {
                close.progress.hiddenCloseAllowed = false
            }
            let serverCount = hidden || windows.isEmpty ? serverWindowCount(pid: pid) : nil
            let decision = close.progress.check(now: ProcessInfo.processInfo.systemUptime,
                originalOpen: originalOpen, windowCount: windows.count, dialogOpen: dialogOpen,
                serverCount: serverCount, appHidden: hidden)
            switch decision {
            case .wait: pending[pid] = close
            case .stop:
                pending.removeValue(forKey: pid)
                let reason: String
                if dialogOpen { reason = "close/save interaction was not completed" }
                else if originalOpen { reason = "window remains open or hide could not be confirmed" }
                else if windows.count > 0 { reason = "another window remains" }
                else if serverCount == nil { reason = "window information is uncertain" }
                else { reason = "another window remains or confirmation expired" }
                onActivity?("\(app.localizedName ?? "App") kept running: \(reason).")
            case .quit:
                pending.removeValue(forKey: pid)
                let accepted = app.terminate()
                onActivity?("\(app.localizedName ?? "App"): normal quit request \(accepted ? "accepted" : "declined").")
            }
        }
        stopCloseTimerIfIdle()
    }

    private func stopCloseTimerIfIdle() {
        guard pending.isEmpty else { return }
        closeTimer?.invalidate()
        closeTimer = nil
    }

    private func cancelHideInference() {
        // An interrupted press/release is no longer a completed close click.
        // Already completed closes can still finish their normal save flow.
        click = nil
        for pid in Array(pending.keys) { pending[pid]?.progress.hiddenCloseAllowed = false }
    }

    private func removeMonitors() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        monitor = nil
        localMonitor = nil
    }

    func stop() {
        enabled = false
        removeMonitors()
        isMonitoring = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        cancelPending()
    }
}
