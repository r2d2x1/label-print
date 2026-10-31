import AppKit
import LabelCore

@MainActor enum FitChecks {
    static func run() throws {
        for tape in [6.0, 9, 12, 18, 24] {
            var doc = LabelDocument.blank; doc.tapeMM = tape
            let item = LabelItem(kind: .icon, content: "square.fill", x: 2, y: 1, width: 2, height: 2)
            doc.items = [item]
            let store = EditorStore(document: doc); store.select(item.id)
            store.fitSelectionToLabel()
            let fitted = store.selected!
            guard abs(fitted.width - fitted.height) < 0.00001,
                  abs(fitted.height - doc.printableHeightMM) < 0.00001,
                  abs(fitted.x + fitted.width / 2 - 20) < 0.00001,
                  abs(fitted.y - doc.printableInsetMM) < 0.00001,
                  store.renderError == nil else { throw RenderError.failed("Fit to printable band failed for \(tape) mm tape") }
            let bitmap = try LabelRenderer.render(store.document)
            let start = (bitmap.height - LabelDocument.printableDots(tape)) / 2
            for y in 0..<bitmap.height where y < start || y >= start + LabelDocument.printableDots(tape) {
                guard bitmap.pixels[y * bitmap.width..<(y + 1) * bitmap.width].allSatisfy({ $0 == 255 }) else {
                    throw RenderError.failed("Fit put ink in shaded unprintable rows")
                }
            }
            store.undo(); guard store.document == doc else { throw RenderError.failed("Fit undo failed") }
        }
        let source = try LabelRenderer.render(.blank)
        var photo = LabelItem(kind: .image, content: "aspect", x: 2, y: 2, width: 4, height: 4)
        photo.imageData = try source.png()
        var doc = LabelDocument.blank; doc.items = [photo]
        let store = EditorStore(document: doc); store.select(photo.id); store.fitSelectionToLabel()
        guard let fitted = store.selected,
              abs(fitted.width / fitted.height - Double(source.width) / Double(source.height)) < 0.00001 else {
            throw RenderError.failed("Image fit ignored intrinsic aspect ratio")
        }
        store.selection = nil
        let count = store.renderCount; store.fitSelectionToLabel()
        guard store.renderCount == count else { throw RenderError.failed("Empty fit selection changed document") }
        print("PASS: fit preserves proportions, centers in exact printable dots on all tapes, excludes shaded rows, honors image aspect and undoes once")
    }
}
