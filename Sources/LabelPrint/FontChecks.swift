import AppKit
import Foundation
import LabelCore

@MainActor enum FontChecks {
    static func run() throws {
        let available = NSFontManager.shared.availableFontFamilies
        guard let family = ["Courier", "Menlo", "Helvetica", "Arial"].first(where: { available.contains($0) }) else {
            throw RenderError.failed("No test font installed")
        }
        var doc = LabelDocument.sample
        let index = doc.items.firstIndex(where: { $0.kind == .text })!
        doc.items[index].fontName = family
        let resolved = doc.items[index].printFont
        guard resolved.familyName == family else { throw RenderError.failed("Chosen font family did not resolve") }
        let restored = try JSONDecoder().decode(LabelDocument.self, from: JSONEncoder().encode(doc))
        guard restored == doc else { throw RenderError.failed("Font was not preserved in saved label") }

        // Existing documents have no fontName field; they must still open.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        var items = legacy["items"] as! [[String: Any]]
        for i in items.indices { items[i].removeValue(forKey: "fontName") }
        legacy["items"] = items
        let old = try JSONDecoder().decode(LabelDocument.self, from: JSONSerialization.data(withJSONObject: legacy)).validated()
        guard old.items.allSatisfy({ $0.fontName == nil }) else { throw RenderError.failed("Legacy font defaults failed") }

        let store = EditorStore(document: .sample)
        let text = store.selected!
        let cached = store.sprites[text.id]!
        let smooth = cached.smoothImage
        let bytes = Array(smooth.dataProvider!.data! as Data)
        guard !store.printDots, smooth.width > cached.image.width,
              stride(from: 3, to: bytes.count, by: 4).contains(where: { bytes[$0] > 0 && bytes[$0] < 255 }) else {
            throw RenderError.failed("Smooth preview did not preserve high-resolution font antialiasing")
        }
        let printBefore = try LabelRenderer.render(store.document).pixels
        store.printDots = true
        guard try LabelRenderer.render(store.document).pixels == printBefore else {
            throw RenderError.failed("Preview mode changed printer pixels")
        }
        store.printDots = false
        print("PASS: smooth high-resolution font preview, antialiased edges, preview mode preserves print raster")
        let original = store.document
        let count = store.spriteRenderCount
        let before = store.preview!.dataProvider!.data! as Data
        store.edit { $0.fontName = family }
        guard store.selected?.printFont.familyName == family, store.spriteRenderCount == count + 1,
              (store.preview!.dataProvider!.data! as Data) != before else {
            throw RenderError.failed("Changing font failed to update preview/cache")
        }
        store.undo()
        guard store.document == original else { throw RenderError.failed("Font change undo failed") }
        store.redo()
        let edited = store.selected!
        let inline = InlineTextEditor(item: edited, scale: 5, autoWidth: true, onChange: { _ in }, onFinish: {})
        let coordinator = inline.makeCoordinator()
        let view = inline.makeEditor(coordinator: coordinator)
        guard view.font?.familyName == edited.printFont.familyName,
              abs((view.font?.pointSize ?? 0) - edited.fontSize * 5 * 25.4 / 72) < 0.001,
              view.selectedRange().length == 0,
              view.selectedRange().location == (edited.content as NSString).length,
              view.focusRingType == .none,
              view.isSelectable,
              (view.selectedTextAttributes[.backgroundColor] as? NSColor) == NSColor.selectedTextBackgroundColor,
              (view.selectedTextAttributes[.foregroundColor] as? NSColor) == NSColor.selectedTextColor else {
            throw RenderError.failed("Inline editor font or selection appearance does not match")
        }
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.moveRightAndModifySelection(nil)
        guard view.selectedRange() == NSRange(location: 0, length: 1) else {
            throw RenderError.failed("Keyboard character selection failed")
        }
        view.setSelectedRange(NSRange(location: 0, length: 3))
        let expected = "Test" + String(edited.content.dropFirst(3))
        view.insertText("Test", replacementRange: view.selectedRange())
        guard view.string == expected else { throw RenderError.failed("Replacing selected characters failed") }
        print("PASS: font selection, shared inline/print font, preview cache invalidation, persistence, legacy files, undo/redo, caret-only start, visible character selection and replacement")
    }
}
