import Foundation
import AppKit
import Vision
import LabelCore

@MainActor enum SelfTest {
    static func run() async throws {
        _ = NSApplication.shared
        try InteractionChecks.run()
        try CloseChecks.run()
        var fixedSample = LabelDocument.sample; fixedSample.autoLength = false
        let sample = try LabelRenderer.render(fixedSample)
        guard sample.width == 425, sample.height == 85,
              Set(sample.pixels).isSubset(of: [0, 255]), sample.pixels.contains(0) else {
            throw RenderError.failed("Monochrome renderer failed")
        }
        var blankDocument = LabelDocument(); blankDocument.items = []
        guard try LabelRenderer.render(blankDocument).pixels.allSatisfy({ $0 == 255 }) else {
            throw RenderError.failed("Blank label contains unexpected ink")
        }
        var iconDocument = blankDocument
        iconDocument.items = [LabelItem(kind: .icon, content: "bolt.fill", x: 2, y: 2, width: 6, height: 6)]
        guard try LabelRenderer.render(iconDocument).pixels.contains(0) else {
            throw RenderError.failed("Icon did not render")
        }
        let png = try sample.png()
        var imageDocument = blankDocument
        var imageItem = LabelItem(kind: .image, content: "test.png", x: 2, y: 2, width: 40, height: 8)
        imageItem.imageData = png; imageDocument.items = [imageItem]
        guard try LabelRenderer.render(imageDocument).pixels.contains(0) else {
            throw RenderError.failed("Imported image did not render")
        }
        guard NSImage(data: png) != nil else { throw RenderError.failed("PNG round-trip failed") }
        let barcode = VNDetectBarcodesRequest(); barcode.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: sample.image).perform([barcode])
        guard barcode.results?.contains(where: { $0.payloadStringValue == "https://example.com/box-a" }) == true else {
            throw RenderError.failed("Rendered QR code did not decode")
        }
        var tooSmall = LabelDocument.sample
        tooSmall.items[0].width = 1; tooSmall.items[0].height = 1
        do { _ = try LabelRenderer.render(tooSmall); throw RenderError.failed("Tiny QR was accepted") }
        catch let error as RenderError {
            guard error.localizedDescription.contains("too small") else { throw error }
        }
        try DragChecks.run()
        try FontChecks.run()
        try AlignmentChecks.run()
        try FitChecks.run()
        try ClipboardChecks.run()
        let fresh = EditorStore()
        guard fresh.document.items.isEmpty, fresh.document.effectiveLengthMM == 40,
              !fresh.document.autoLength, fresh.selectionIDs.isEmpty, !fresh.dirty,
              !fresh.history.canUndo, fresh.renderError == nil,
              try LabelRenderer.render(fresh.document).pixels.allSatisfy({ $0 == 255 }) else {
            throw RenderError.failed("Startup must be a blank fixed 40 mm label")
        }
        fresh.document = .sample
        fresh.newLabel()
        guard fresh.document == .blank, fresh.selectionIDs.isEmpty, !fresh.dirty else {
            throw RenderError.failed("New label must reset to blank 40 mm")
        }
        print("PASS: empty fixed 40 mm startup and new label, no selection or dirty state")
        let store = EditorStore(document: .sample)
        let original = store.document
        let fittedLength = store.document.effectiveLengthMM
        guard fittedLength < 59 else { throw RenderError.failed("Text length did not fit") }
        let textID = store.document.items.first(where: { $0.kind == .text })!.id
        store.editText(id: textID, content: "A much longer storage box heading")
        guard store.document.effectiveLengthMM > fittedLength else { throw RenderError.failed("Typing did not grow the label") }
        store.undo()
        store.setLength(65)
        guard !store.document.autoLength, store.document.effectiveLengthMM == 65 else { throw RenderError.failed("Manual length failed") }
        store.fitLengthToContent()
        guard store.document.autoLength, store.document.effectiveLengthMM == fittedLength else { throw RenderError.failed("Fit to Content failed") }
        store.undo(); store.undo()
        let oldCount = store.document.items.count
        store.add(.text); guard store.document.items.count == oldCount + 1 else { throw RenderError.failed("Insert failed") }
        store.edit { $0.x = -100; $0.height = 100 }
        guard store.selected?.x == 0, store.selected?.height == 12 else { throw RenderError.failed("Bounds clamping failed") }
        store.undo(); store.undo()
        guard store.document == original else { throw RenderError.failed("Editor undo failed") }
        store.redo()
        guard store.document.items.count == oldCount + 1 else { throw RenderError.failed("Editor redo failed") }
        var editedText = ""
        let inlineItem = LabelDocument.sample.items.first(where: { $0.kind == .text })!
        let inline = InlineTextEditor(item: inlineItem, scale: 5, autoWidth: true,
                                      onChange: { editedText = $0 }, onFinish: {})
        let coordinator = inline.makeCoordinator()
        let textView = inline.makeEditor(coordinator: coordinator)
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
        textView.insertText("Typed directly on the label", replacementRange: textView.selectedRange())
        guard textView.string == "Typed directly on the label", editedText == textView.string,
              textView.textContainerInset == .zero, textView.window == nil else {
            throw RenderError.failed("Embedded text editor typing did not update content")
        }
        try FileManager.default.createDirectory(atPath: ".build/test-artifacts", withIntermediateDirectories: true)
        try png.write(to: URL(fileURLWithPath: ".build/test-artifacts/sample-label.png"))
        print("PASS: monochrome/text/image/icon rendering, blank label, PNG encoding, QR decoding, tiny-QR rejection, editor insertion, clamping, undo/redo, measured text fitting, manual length, embedded NSTextView typing")
        if CommandLine.arguments.contains("--probe-printer") {
            let response = try await PrinterService().status()
            print("Printer probe: \(response.ok ? "ready" : "unavailable") — \(response.message)")
        }
    }
}

@main enum EntryPoint {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--interaction-test") {
            do { try InteractionChecks.run() }
            catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        } else if let index = CommandLine.arguments.firstIndex(of: "--pdf-print-file"), CommandLine.arguments.count > index + 2 {
            do { try SheetPDFCalibration.fileOnly(
                input: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                output: URL(fileURLWithPath: CommandLine.arguments[index + 2])) }
            catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        } else if CommandLine.arguments.contains("--pdf-size-audit") {
            do { try SheetPDFCalibration.run() }
            catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        } else if CommandLine.arguments.contains("--editor-checks") {
            do {
                _ = NSApplication.shared
                try CloseChecks.run(); try DragChecks.run(); try FontChecks.run()
                try AlignmentChecks.run(); try FitChecks.run(); try ClipboardChecks.run()
            } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        } else if CommandLine.arguments.contains("--sheet-test") {
            do { try SheetChecks.run() }
            catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        } else if CommandLine.arguments.contains("--print-margin-test") {
            do { try await PrintMarginTest.run() }
            catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        } else if CommandLine.arguments.contains("--drag-benchmark") {
            do { try DragBenchmark.run() }
            catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        } else if CommandLine.arguments.contains("--self-test") {
            do { try await SelfTest.run() }
            catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
        } else {
            LabelPrintApp.main()
        }
    }
}
