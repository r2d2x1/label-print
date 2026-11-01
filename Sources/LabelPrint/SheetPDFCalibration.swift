import AppKit
import PDFKit
import LabelCore

/// Writes PDF-only diagnostic jobs. This command never spools a physical print job.
@MainActor enum SheetPDFCalibration {
    static func fileOnly(input: URL, output: URL) throws {
        _ = NSApplication.shared
        let data = try Data(contentsOf: input)
        let view = try SheetPrintView(data: data)
        let info = SheetPrintSettings.make(printerName: "EPSON ET-5880")
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
        guard info.jobDisposition == .save else { throw RenderError.failed("PDF-only disposition was not set") }
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false; operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: output.path) else {
            throw RenderError.failed("Could not save actual-job print PDF")
        }
        for (pdf, suffix) in [(input, "source"), (output, "system")] {
            let image = try SheetRenderer.preview(Data(contentsOf: pdf))
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: output.deletingLastPathComponent().appendingPathComponent("actual-job-\(suffix).png"))
        }
        print("Saved PDF-only actual job: \(output.path)")
    }
    static func run() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: "output/pdf/size-audit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let provider = CGDataProvider(data: Data(repeating: 0, count: 1000 * 10) as CFData)!
        let bar = CGImage(width: 1000, height: 10, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 1000,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider,
                          decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let barPNG = NSBitmapImageRep(cgImage: bar).representation(using: .png, properties: [:])!
        for template in SheetTemplate.all {
            var sheet = SheetLayout(templateID: template.id)
            for index in sheet.labels.indices {
                var text = LabelItem(kind: .text,
                    content: "\(template.id) / \(index + 1) / \(template.width) x \(template.height) mm",
                    x: 3, y: 3, width: min(65, template.width - 6), height: 5)
                text.fontSize = 8
                var reference = LabelItem(kind: .image, content: "50 mm reference bar", x: 5, y: 12, width: 50, height: 0.5)
                reference.imageData = barPNG
                sheet.labels[index] = [text, reference]
            }
            var doc = LabelDocument.blank
            doc.sheet = sheet; doc.autoLength = false
            doc.lengthMM = template.width; doc.tapeMM = template.height; doc.items = sheet.labels[0]
            let data = try SheetRenderer.pdf(doc)
            let source = directory.appendingPathComponent("avery-\(template.id)-source.pdf")
            try data.write(to: source)
            let view = try SheetPrintView(data: data)
            let info = SheetPrintSettings.make(printerName: EditorStore.a4Printers().first)
            let output = directory.appendingPathComponent("avery-\(template.id)-system-print.pdf")
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
            guard info.jobDisposition == .save else { throw RenderError.failed("PDF-only disposition was not set") }
            let operation = NSPrintOperation(view: view, printInfo: info)
            operation.showsPrintPanel = false; operation.showsProgressPanel = false
            guard operation.run(), FileManager.default.fileExists(atPath: output.path) else {
                throw RenderError.failed("macOS could not save PDF-only print output")
            }
            let preview = try SheetRenderer.preview(data)
            let png = NSBitmapImageRep(cgImage: preview).representation(using: .png, properties: [:])!
            try png.write(to: directory.appendingPathComponent("avery-\(template.id)-source.png"))
            let printedPreview = try SheetRenderer.preview(Data(contentsOf: output))
            let printedPNG = NSBitmapImageRep(cgImage: printedPreview).representation(using: .png, properties: [:])!
            try printedPNG.write(to: directory.appendingPathComponent("avery-\(template.id)-system-print.png"))
            print("\(template.id): source + macOS print PDF; printer=\(info.printer.name); paper=\(info.paperSize); scale=\(info.scalingFactor); imageable=\(info.imageablePageBounds)")
        }
    }
}
