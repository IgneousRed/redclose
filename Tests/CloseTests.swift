import AppKit

@main
enum CloseTests {
    static func main() {
        var cases = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            cases += 1
        }
        var state = CloseProgress(started: 0)
        expect(state.check(now: 0.1, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 0) == .wait,
               "A single empty snapshot must not quit")
        expect(state.check(now: 0.31, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 0) == .quit,
               "A closed last window must quit after confirmation")
        state = CloseProgress(started: 0)
        expect(state.check(now: 0.1, originalOpen: false, windowCount: 1, dialogOpen: false, serverCount: 0) == .stop,
               "Another AX window, including a minimized window, must prevent quitting")
        state = CloseProgress(started: 0)
        expect(state.check(now: 0.1, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 1) == .wait,
               "A full-screen or other-Space window must prevent quitting")
        expect(state.check(now: 1.2, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 1) == .stop,
               "An existing offscreen window must end the attempt")
        state = CloseProgress(started: 0)
        expect(state.check(now: 0.1, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: nil) == .stop,
               "Window server failure must leave the app running")
        state = CloseProgress(started: 0)
        expect(state.check(now: 1.1, originalOpen: true, windowCount: 1, dialogOpen: false, serverCount: nil) == .stop,
               "A cancelled close must be forgotten")
        state = CloseProgress(started: 0)
        expect(state.check(now: 30, originalOpen: true, windowCount: 1, dialogOpen: true, serverCount: nil) == .wait,
               "A save prompt must be allowed to finish")
        expect(state.check(now: 31, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 0) == .wait,
               "Saving must still require an empty-window confirmation")
        expect(state.check(now: 31.3, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 0) == .quit,
               "Saving and closing the last window must quit")
        state = CloseProgress(started: 0)
        _ = state.check(now: 0.1, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 1)
        _ = state.check(now: 0.2, originalOpen: true, windowCount: 1, dialogOpen: true, serverCount: nil)
        expect(state.check(now: 30, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 1) == .wait,
               "A window returning for a save prompt must reset its old disappearance grace")
        expect(state.check(now: 30.2, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 0) == .wait,
               "Post-save animation still requires empty-window confirmation")
        expect(state.check(now: 30.5, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 0) == .quit,
               "The completed post-save close must not inherit an expired animation deadline")
        state = CloseProgress(started: 0)
        expect(state.check(now: 301, originalOpen: true, windowCount: 1, dialogOpen: true, serverCount: nil) == .stop,
               "Pending clicks must not survive indefinitely")
        state = CloseProgress(started: 0)
        _ = state.check(now: 0.1, originalOpen: false, windowCount: 0, dialogOpen: false, serverCount: 0)
        expect(state.check(now: 0.4, originalOpen: false, windowCount: 1, dialogOpen: false, serverCount: 1) == .stop,
               "A new window appearing before confirmation must prevent quitting")

        state = CloseProgress(started: 0, hiddenCloseAllowed: true)
        expect(state.check(now: 0.1, originalOpen: true, windowCount: 1, dialogOpen: false,
                           serverCount: 0, appHidden: true) == .wait,
               "Hiding a retained last window must require confirmation")
        expect(state.check(now: 0.31, originalOpen: true, windowCount: 1, dialogOpen: false,
                           serverCount: 0, appHidden: true) == .quit,
               "A confirmed hide after a last-window close click must quit")
        state = CloseProgress(started: 0, hiddenCloseAllowed: true)
        _ = state.check(now: 0.1, originalOpen: true, windowCount: 1, dialogOpen: false,
                        serverCount: 0, appHidden: true)
        expect(state.check(now: 0.31, originalOpen: true, windowCount: 1, dialogOpen: false,
                           serverCount: nil, appHidden: false) == .wait,
               "Unhiding before confirmation must cancel the hidden confirmation")
        expect(state.check(now: 0.4, originalOpen: true, windowCount: 1, dialogOpen: false,
                           serverCount: 0, appHidden: true) == .wait,
               "A second hide must start a fresh confirmation")
        state.hiddenCloseAllowed = false
        expect(state.check(now: 0.7, originalOpen: true, windowCount: 1, dialogOpen: false,
                           serverCount: 0, appHidden: true) == .stop,
               "An intervening user gesture must revoke an in-progress hide attempt")
        for (original, count) in [(true, 1), (false, 0)] {
            state = CloseProgress(started: 0)
            expect(state.check(now: 0.1, originalOpen: original, windowCount: count, dialogOpen: false,
                               serverCount: 0, appHidden: true) == .stop,
                   "Hiding without a sole-window snapshot must not quit, even if AX drops all windows")
        }
        for (original, count) in [(true, 2), (false, 1)] {
            state = CloseProgress(started: 0, hiddenCloseAllowed: true)
            expect(state.check(now: 0.1, originalOpen: original, windowCount: count, dialogOpen: false,
                               serverCount: 0, appHidden: true) == .stop,
                   "Another or replacement AX window must block a hidden quit")
        }
        state = CloseProgress(started: 0, hiddenCloseAllowed: true)
        expect(state.check(now: 0.1, originalOpen: true, windowCount: 1, dialogOpen: false,
                           serverCount: nil, appHidden: true) == .stop,
               "An unknown server result must block a hidden quit")
        state = CloseProgress(started: 0, hiddenCloseAllowed: true)
        expect(state.check(now: 0.1, originalOpen: true, windowCount: 1, dialogOpen: false,
                           serverCount: 1, appHidden: true) == .wait,
               "A still-visible or other-Space window must block quitting during hide animation")
        expect(state.check(now: 1.1, originalOpen: true, windowCount: 1, dialogOpen: false,
                           serverCount: 1, appHidden: true) == .stop,
               "A persistent server window must end the hide attempt")
        state = CloseProgress(started: 0, hiddenCloseAllowed: true)
        expect(state.check(now: 1.1, originalOpen: true, windowCount: 1, dialogOpen: false,
                           serverCount: 0, appHidden: true) == .stop,
               "A late hide must not be attributed to an old click")
        state = CloseProgress(started: 0, hiddenCloseAllowed: true)
        expect(state.check(now: 0.1, originalOpen: true, windowCount: 1, dialogOpen: true,
                           serverCount: 0, appHidden: true) == .stop,
               "Hiding with a save prompt must not quit")
        state = CloseProgress(started: 0, hiddenCloseAllowed: true)
        _ = state.check(now: 0.1, originalOpen: true, windowCount: 1, dialogOpen: true, serverCount: nil)
        expect(state.check(now: 0.4, originalOpen: true, windowCount: 1, dialogOpen: false,
                           serverCount: 0, appHidden: true) == .stop,
               "A save interaction must prevent attributing a subsequent hide to the click")
        state = CloseProgress(started: 0, hiddenCloseAllowed: true)
        _ = state.check(now: 0.1, originalOpen: false, windowCount: 0, dialogOpen: false,
                        serverCount: 0, appHidden: true)
        expect(state.check(now: 0.31, originalOpen: false, windowCount: 0, dialogOpen: false,
                           serverCount: 0, appHidden: true) == .quit,
               "A hidden sole window can also disappear from AX entirely")
        let app = NSRunningApplication.current
        let click = CloseClick(app: app, window: AXUIElementCreateApplication(app.processIdentifier),
                               buttonFrame: CGRect(x: -100, y: 50, width: 14, height: 14), hiddenCloseAllowed: false)
        expect(click.acceptsRelease(at: CGPoint(x: -95, y: 55)), "Negative screen coordinates must work")
        expect(!click.acceptsRelease(at: CGPoint(x: -60, y: 55)), "Dragging off the close button must cancel")
        expect(!eligible(app), "The utility must not quit itself")
        expect(serverWindowCount(pid: -1) == 0, "Window server dictionaries must decode on this macOS version")
        print("Passed \(cases) checks")
    }
}
