import AppKit

@MainActor enum CloseChecks {
    static func run() throws {
        let delegate = AppDelegate()
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        var confirmations = 0
        var allow = true
        var reply: NSApplication.TerminateReply = .terminateCancel
        delegate.confirmClose = { confirmations += 1; return allow }
        delegate.requestTermination = { reply = delegate.applicationShouldTerminate(NSApp) }
        guard !delegate.windowShouldClose(window), confirmations == 1, reply == .terminateNow else {
            throw RenderError.failed("Window close did not use exactly one quit confirmation")
        }
        allow = false
        guard !delegate.windowShouldClose(window), confirmations == 2, reply == .terminateCancel else {
            throw RenderError.failed("Canceled close must keep the window and app open")
        }
        allow = true
        guard delegate.applicationShouldTerminate(NSApp) == .terminateNow, confirmations == 3 else {
            throw RenderError.failed("Quit must use exactly one confirmation after canceled close")
        }
        let clean = AppDelegate(); let cleanStore = EditorStore(); clean.store = cleanStore
        guard withExtendedLifetime(cleanStore, { clean.applicationShouldTerminate(NSApp) }) == .terminateNow else {
            throw RenderError.failed("Clean document could not quit")
        }
        print("PASS: close and Quit share one confirmation; cancel keeps window open and later Quit confirms again")
    }
}
