import SwiftUI
import AppKit
import LabelCore

/// A native text view positioned inside the label, using the same typography
/// and physical scale as the renderer. It is an editor overlay, never printed.
struct InlineTextEditor: NSViewRepresentable {
    let item: LabelItem
    let scale: Double
    let autoWidth: Bool
    var selectAllOnStart = false
    let onChange: (String) -> Void
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextView { makeEditor(coordinator: context.coordinator) }
    // Kept separate so native text editing can be tested without a visible window.
    func makeEditor(coordinator: Coordinator) -> NSTextView {
        let view = CanvasTextView()
        view.delegate = coordinator
        view.finish = { coordinator.parent.onFinish() }
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isVerticallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.backgroundColor = .white
        view.textColor = .black
        view.insertionPointColor = .black
        view.focusRingType = .none
        view.isSelectable = true
        view.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor,
                                       .foregroundColor: NSColor.selectedTextColor]
        view.setAccessibilityLabel("Edit label text directly")
        configure(view)
        view.string = item.content
        let count = (view.string as NSString).length
        view.setSelectedRange(selectAllOnStart ? NSRange(location: 0, length: count) : NSRange(location: count, length: 0))
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        configure(view)
        // Do not replace the string while typing: preserve caret, selection,
        // and marked text used by input methods.
        if view.string != item.content && !view.hasMarkedText() {
            let selection = view.selectedRange()
            view.string = item.content
            let location = min(selection.location, (view.string as NSString).length)
            let length = min(selection.length, (view.string as NSString).length - location)
            view.setSelectedRange(NSRange(location: location, length: length))
        }
    }
    private func configure(_ view: NSTextView) {
        view.font = item.resolvedFont(ofSize: item.fontSize * scale * 25.4 / 72)
        view.alignment = item.alignment == "center" ? .center : item.alignment == "right" ? .right : .left
        view.textContainer?.widthTracksTextView = !autoWidth
        if autoWidth { view.textContainer?.containerSize = NSSize(width: 1_000_000, height: 1_000_000) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineTextEditor
        init(_ parent: InlineTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.onChange(view.string)
        }
    }
}

private final class CanvasTextView: NSTextView {
    var finish: (() -> Void)?
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { DispatchQueue.main.async { [weak self] in self?.finish?() } }
        return result
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || event.keyCode == 48 || (event.keyCode == 36 && event.modifierFlags.contains(.command)) {
            finish?()
        } else { super.keyDown(with: event) }
    }
}
