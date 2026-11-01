import SwiftUI
import AppKit
import LabelCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var store: EditorStore?
    // Both the red close button and Quit use the same termination decision.
    // Injectable actions let regression checks exercise cancellation without
    // dismissing real dialogs or terminating the test process.
    var requestTermination: () -> Void = { NSApp.terminate(nil) }
    var confirmClose: (() -> Bool)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestTermination()
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (confirmClose?() ?? store?.canClose() ?? true) ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct LabelPrintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store: EditorStore = {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["LABELPRINT_TEST_DOCUMENT"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let document = try? JSONDecoder().decode(LabelCore.LabelDocument.self, from: data).validated() {
            let store = EditorStore(document: document)
            if store.isA4 { store.printerName = "A4 / PDF" }
            return store
        }
        #endif
        return EditorStore()
    }()
    var body: some Scene {
        Window("LabelPrint", id: "main") {
            EditorView(store: store)
                .background(EditorWindowBinding(delegate: delegate))
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Label") { store.newLabel() }.keyboardShortcut("n")
                Button("Open…") { store.open() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { store.save() }.keyboardShortcut("s")
                Button("Save As…") { store.save(as: true) }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button(store.isA4 ? "Export PDF…" : "Export PNG…") { store.export() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undo() }.keyboardShortcut("z").disabled(!store.history.canUndo)
                Button("Redo") { store.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!store.history.canRedo)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }.keyboardShortcut("x")
                Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }.keyboardShortcut("c")
                Button("Paste") { store.paste() }.keyboardShortcut("v")
                Button("Paste Image") { store.pasteImage() }.keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button(store.isA4 ? "Print Sheet…" : "Print Label") { Task { await store.printLabel() } }.keyboardShortcut("p").disabled(store.busy)
            }
        }
    }
}

/// SwiftUI owns window sizing and presentation. This bridge only installs the
/// close delegate; hiding/showing or resizing here races scene presentation.
struct EditorWindowBinding: NSViewRepresentable {
    let delegate: AppDelegate
    func makeNSView(context: Context) -> BindingView {
        let view = BindingView()
        view.appDelegate = delegate
        return view
    }
    func updateNSView(_ view: BindingView, context: Context) {
        view.appDelegate = delegate
        view.window?.delegate = delegate
    }
    final class BindingView: NSView {
        weak var appDelegate: AppDelegate?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.delegate = appDelegate
        }
    }
}
