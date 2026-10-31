import Foundation
import LabelCore

@MainActor enum AlignmentChecks {
    static func run() throws {
        var doc = LabelDocument(); doc.autoLength = false
        let a = LabelItem(kind: .icon, content: "star", x: 2, y: 1, width: 4, height: 4)
        let b = LabelItem(kind: .icon, content: "bolt", x: 12, y: 6, width: 8, height: 5)
        let untouched = LabelItem(kind: .text, content: "Unselected", x: 30, y: 2, width: 25, height: 4)
        doc.items = [a, b, untouched]
        let ids: Set<UUID> = [a.id, b.id]
        for mode in ItemAlignment.allCases {
            var aligned = doc; aligned.align(ids, to: mode)
            let x = aligned.items[0], y = aligned.items[1]
            let valid: Bool
            switch mode {
            case .left: valid = x.x == 2 && y.x == 2
            case .horizontalCenter: valid = x.x + x.width / 2 == 11 && y.x + y.width / 2 == 11
            case .right: valid = x.x + x.width == 20 && y.x + y.width == 20
            case .top: valid = x.y == 1 && y.y == 1
            case .verticalCenter: valid = x.y + x.height / 2 == 6 && y.y + y.height / 2 == 6
            case .bottom: valid = x.y + x.height == 11 && y.y + y.height == 11
            }
            guard valid, aligned.items[2] == untouched else { throw RenderError.failed("Incorrect alignment: \(mode)") }
            _ = try aligned.validated()
        }
        var auto = LabelDocument.sample
        let textIDs = Set(auto.items.filter { $0.kind == .text }.map(\.id))
        auto.align(textIDs, to: .right)
        let text = auto.items.filter { textIDs.contains($0.id) }
        guard abs((text[0].x + auto.itemWidthMM(text[0])) - (text[1].x + auto.itemWidthMM(text[1]))) < 0.00001 else {
            throw RenderError.failed("Text alignment used empty box width")
        }
        let store = EditorStore(document: .sample); store.change { $0 = doc }
        store.select(a.id); store.select(b.id, extending: true)
        guard store.selectionIDs == ids, store.selected == nil else { throw RenderError.failed("Command selection did not add item") }
        store.select(a.id, extending: true)
        guard store.selection == b.id else { throw RenderError.failed("Command selection did not remove item") }
        store.select(b.id, extending: true)
        guard store.selectionIDs.isEmpty else { throw RenderError.failed("Command selection did not clear last item") }
        store.select(a.id); store.select(b.id, extending: true)
        store.alignSelection(.right)
        store.undo()
        guard store.document == doc, store.selectionIDs == ids else { throw RenderError.failed("Alignment undo or selection failed") }
        let renders = store.renderCount
        let moved = store.drag(id: a.id, dx: 9999, dy: 9999)!
        let other = store.draggedItems[b.id]!
        guard store.renderCount == renders, store.document == doc,
              moved.x == 42, other.x == 52, moved.y == 2, other.y == 7 else {
            throw RenderError.failed("Group drag did not preserve spacing/bounds or rerendered")
        }
        store.endGesture(); store.undo()
        guard store.document == doc else { throw RenderError.failed("Group drag did not undo as one action") }
        store.duplicate()
        guard store.document.items.count == 5, store.selectionIDs.count == 2,
              store.selectionIDs.isDisjoint(with: ids) else { throw RenderError.failed("Multi-duplicate failed") }
        store.delete()
        guard store.document == doc, store.selectionIDs.isEmpty else { throw RenderError.failed("Multi-delete removed wrong items") }
        store.select(a.id); store.select(b.id)
        guard store.selectionIDs == [b.id] else { throw RenderError.failed("Plain click did not replace selection") }
        store.alignSelection(.left)
        guard store.selected?.x == 0 else { throw RenderError.failed("Single-item alignment failed") }
        store.undo()
        guard store.document == doc else { throw RenderError.failed("Single alignment undo failed") }
        for mode in ItemAlignment.allCases {
            var single = doc; single.align([a.id], to: mode)
            let result = single.items[0]
            let valid: Bool
            switch mode {
            case .left: valid = result.x == 0
            case .horizontalCenter: valid = result.x + result.width / 2 == doc.lengthMM / 2
            case .right: valid = result.x + result.width == doc.lengthMM
            case .top: valid = result.y == doc.printableInsetMM
            case .verticalCenter: valid = abs(result.y + result.height / 2 - (doc.printableInsetMM + doc.printableBottomMM) / 2) < 0.00001
            case .bottom: valid = result.y + result.height == doc.printableBottomMM
            }
            guard valid, single.items[1] == b else { throw RenderError.failed("Single alignment incorrect: \(mode)") }
        }
        store.select(a.id)
        let renderCount = store.renderCount
        let snapped = store.drag(id: a.id, dx: 25.8, dy: 2.9, snapToleranceMM: 0.3)!
        guard snapped.x == 28, snapped.y == 4, store.snapX == 30, store.snapY == 6,
              store.renderCount == renderCount, store.document == doc else {
            throw RenderError.failed("Center snapping/guide or cached dragging failed")
        }
        store.endGesture()
        guard store.snapX == nil, store.snapY == nil else { throw RenderError.failed("Snap guides persisted after drop") }
        store.undo()
        guard store.document == doc else { throw RenderError.failed("Snapped drag undo failed") }
        let edge = store.drag(id: a.id, dx: -1.9, dy: 0, snapToleranceMM: 0.3)!
        guard edge.x == 0, store.snapX == 0 else { throw RenderError.failed("Edge snap failed") }
        store.endGesture(); store.undo()
        let free = store.drag(id: a.id, dx: 5.5, dy: 0, snapToleranceMM: 0.1)!
        guard free.x == 7.5, store.snapX == nil else { throw RenderError.failed("Snapping captured a distant target") }
        store.endGesture(); store.undo()
        print("PASS: single-item label alignment, edge/center snapping, transient dashed guide coordinates, snap undo and no per-event rendering")
        print("PASS: Command selection toggling, six alignments, visible text bounds, unaffected objects, alignment/group-drag undo, group bounds, multi-duplicate/delete")
    }
}
