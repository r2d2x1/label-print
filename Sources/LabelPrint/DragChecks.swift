import AppKit
import LabelCore

@MainActor enum DragChecks {
    static func run() throws {
        let store = EditorStore(document: .sample)
        let original = store.document
        let item = original.items.first(where: { $0.kind == .text })!
        let renders = store.renderCount, sprites = store.spriteRenderCount
        let preview = store.preview
        let originalLength = original.effectiveLengthMM
        for step in 1...120 {
            let moved = store.drag(id: item.id, dx: Double(step) / 120 * 8, dy: 0)
            guard moved?.x == item.x + Double(step) / 120 * 8,
                  store.document == original, store.renderCount == renders,
                  store.spriteRenderCount == sprites, store.preview === preview,
                  store.document.effectiveLengthMM == originalLength else {
                throw RenderError.failed("Drag rerendered, changed zoom inputs, or failed to track the pointer")
            }
        }
        store.endGesture()
        let movedDocument = store.document
        guard movedDocument.items.first(where: { $0.id == item.id })?.x == item.x + 8,
              store.renderCount == renders + 1, store.spriteRenderCount == sprites,
              movedDocument.effectiveLengthMM > originalLength else {
            throw RenderError.failed("Drop did not commit once and reuse sprites")
        }
        let expected = try LabelRenderer.render(movedDocument)
        guard let actual = store.preview?.dataProvider?.data,
              (actual as Data) == (expected.image.dataProvider!.data! as Data) else {
            throw RenderError.failed("Committed preview differs from the print/export renderer")
        }
        store.undo()
        guard store.document == original else { throw RenderError.failed("Drag was not one undo step") }
        store.redo()
        guard store.document == movedDocument else { throw RenderError.failed("Drag redo failed") }

        // Transparent text pixels must not erase artwork below the moving text.
        let textSprite = store.sprites[item.id]!.image
        let data = textSprite.dataProvider!.data! as Data
        let alpha = stride(from: 3, to: data.count, by: 4).map { data[$0] }
        guard alpha.contains(0), alpha.contains(where: { $0 > 0 }) else {
            throw RenderError.failed("Text sprite lost transparency or ink")
        }
        let oldSpriteCount = store.spriteRenderCount
        store.editText(id: item.id, content: "A different heading")
        guard store.spriteRenderCount == oldSpriteCount + 1 else {
            throw RenderError.failed("Content edits did not invalidate only the changed sprite")
        }

        let noOp = EditorStore(document: .sample)
        let count = noOp.renderCount
        noOp.drag(id: noOp.document.items[0].id, dx: 0, dy: 0); noOp.endGesture()
        guard noOp.renderCount == count, !noOp.history.canUndo else {
            throw RenderError.failed("Unmoved item created a render or undo step")
        }
        let box = EditorStore(document: .sample); box.setLength(60)
        let qr = box.document.items[0]
        let bounded = box.drag(id: qr.id, dx: 9999, dy: 9999)!
        guard bounded.x + bounded.width == 60, bounded.y + bounded.height == 12 else {
            throw RenderError.failed("Drag bounds were not preserved")
        }
        box.endGesture(); _ = try box.document.validated()
        let prior = box.document
        let resized = box.drag(id: qr.id, dx: -2, dy: -2, resize: true)!
        guard box.document == prior, resized.width == qr.width - 2 else {
            throw RenderError.failed("Resize did not use the transient preview")
        }
        box.endGesture(); box.undo()
        guard box.document == prior else { throw RenderError.failed("Resize undo failed") }
        print("PASS: drag avoids per-event rendering, caches transparent sprites, freezes auto-length until drop, commits exact bitmap once, undo/redo, bounds, resizing, and cache invalidation")
    }
}
