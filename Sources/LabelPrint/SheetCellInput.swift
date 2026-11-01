import SwiftUI
import AppKit

/// Native click-count handling keeps the first click from replacing the page
/// before the second click can enter text editing.
struct SheetCellInput: NSViewRepresentable {
    let label: String
    let editPoint: CGPoint?
    let activate: (CGPoint, Bool) -> Void
    func makeNSView(context: Context) -> CellView {
        let view = CellView(frame: .zero)
        configure(view)
        return view
    }
    func updateNSView(_ view: CellView, context: Context) { configure(view) }
    private func configure(_ view: CellView) {
        view.activate = activate; view.editPoint = editPoint
        view.setAccessibilityElement(true); view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(label)
        view.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Edit Contents", handler: { [weak view] in
            guard let view else { return false }
            view.activate(view.editPoint ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY), true)
            return true
        })])
    }
    static func dismantleNSView(_ view: CellView, coordinator: ()) { view.pending?.cancel() }
    final class CellView: NSView {
        var activate: (CGPoint, Bool) -> Void = { _, _ in }
        var editPoint: CGPoint?
        var pending: DispatchWorkItem?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            handleClick(point: point, count: event.clickCount)
        }
        func handleClick(point: CGPoint, count: Int) {
            pending?.cancel()
            if count >= 2 {
                DispatchQueue.main.async { [weak self] in self?.activate(point, true) }
            } else {
                let work = DispatchWorkItem { [weak self] in self?.activate(point, false) }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
            }
        }
        override func accessibilityPerformPress() -> Bool {
            activate(CGPoint(x: bounds.midX, y: bounds.midY), false)
            return true
        }
        deinit { pending?.cancel() }
    }
}
