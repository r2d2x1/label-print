import AppKit
import PDFKit
import LabelCore

@MainActor enum SheetChecks {
    static func run() throws {
        _ = NSApplication.shared
        let store = EditorStore()
        store.choosePrinter("A4 / PDF")
        guard store.isA4, store.document.lengthMM == 210, store.document.tapeMM == 297 else {
            throw RenderError.failed("A4 printer selection did not create A4 paper")
        }
        store.setTemplate("3475")
        store.add(.text, content: "SOURCE LABEL")
        store.edit { $0.width = 50; $0.height = 10; $0.fontSize = 14 }
        store.editSheet { $0.printPositions = [0, 2]; $0.cutLines = false }
        let before = store.document
        store.copyLabel(to: [0, 1, 2, 5])
        guard let copied = store.document.sheet,
              copied.labels[0] == before.items,
              copied.labels[1][0].content == "SOURCE LABEL",
              copied.labels[1][0].id != copied.labels[2][0].id,
              copied.printPositions == [0, 2] else { throw RenderError.failed("Copy changed source, IDs or print positions") }
        store.undo()
        guard store.document == before else { throw RenderError.failed("Copy was not one undo step") }
        store.redo()
        store.selectLabel(1)
        store.selection = store.document.items[0].id
        store.edit { $0.content = "INDEPENDENT" }
        guard store.document.sheet!.labels[0][0].content == "SOURCE LABEL",
              store.document.sheet!.labels[1][0].content == "INDEPENDENT" else {
            throw RenderError.failed("Copied labels are linked")
        }
        let restored = try JSONDecoder().decode(LabelDocument.self, from: JSONEncoder().encode(store.document)).validated()
        guard restored == store.document else { throw RenderError.failed("Sheet round-trip failed") }
        let data = try SheetRenderer.pdf(restored)
        guard let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) else { throw RenderError.failed("No PDF page") }
        let bounds = page.bounds(for: .mediaBox)
        guard abs(bounds.width - 210 * 72 / 25.4) < 0.01,
              abs(bounds.height - 297 * 72 / 25.4) < 0.01 else { throw RenderError.failed("PDF is not actual A4 size") }
        let text = page.string ?? ""
        guard text.components(separatedBy: "SOURCE LABEL").count == 3, !text.contains("INDEPENDENT") else {
            throw RenderError.failed("PDF does not honor selected print positions: \(text)")
        }
        let preview = try SheetRenderer.preview(SheetRenderer.pdf(restored, printOnly: false))
        let emptyStore = EditorStore()
        emptyStore.choosePrinter("A4 / PDF"); emptyStore.setTemplate("3475")
        let blank = try SheetRenderer.pdf(emptyStore.document)
        emptyStore.editSheet { $0.cutLines = false }
        let noCuts = try SheetRenderer.pdf(emptyStore.document)
        let cutImage = try SheetRenderer.preview(blank)
        let noCutImage = try SheetRenderer.preview(noCuts)
        guard (cutImage.dataProvider?.data as Data?) != (noCutImage.dataProvider?.data as Data?) else {
            throw RenderError.failed("Cut lines were not added to PDF output")
        }
        emptyStore.editSheet { $0.plainPaper = false; $0.cutLines = true }
        let labelPaper = try SheetRenderer.preview(SheetRenderer.pdf(emptyStore.document))
        guard (labelPaper.dataProvider?.data as Data?) == (noCutImage.dataProvider?.data as Data?) else {
            throw RenderError.failed("Precut label sheets must not print cut lines")
        }
        let savedSheet = store.document
        store.choosePrinter("PT-2430PC")
        guard !store.isA4 else { throw RenderError.failed("Tape mode did not restore") }
        store.choosePrinter("A4 / PDF")
        guard store.document == savedSheet else { throw RenderError.failed("Mode switch lost sheet contents") }
        try FileManager.default.createDirectory(atPath: ".build/test-artifacts", withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: ".build/test-artifacts/a4-sheet.pdf"))
        let png = NSBitmapImageRep(cgImage: preview).representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: ".build/test-artifacts/a4-sheet-preview.png"))
        print("PASS: A4 mode, independent one-to-many copies, one-step undo/redo, persistence, selected positions, exact A4 PDF, cut lines and draft restoration")
    }
}
