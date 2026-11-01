import AppKit
import PDFKit
import LabelCore

/// Vector text and native image content in physical page points, independent of canvas zoom.
enum SheetRenderer {
    static let pointsPerMM = 72.0 / 25.4
    static let pageSize = CGSize(width: 210 * pointsPerMM, height: 297 * pointsPerMM)

    static func pdf(_ document: LabelDocument, printOnly: Bool = true) throws -> Data {
        _ = try document.validated()
        guard let sheet = document.sheet else { throw DocumentError.invalid }
        let data = NSMutableData()
        var media = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data),
              let cg = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw RenderError.failed("Could not create A4 PDF")
        }
        cg.beginPDFPage(nil)
        cg.setFillColor(NSColor.white.cgColor); cg.fill(media)
        for index in sheet.labels.indices where !printOnly || sheet.printPositions.contains(index) {
            let cell = sheet.template.rect(at: index)
            cg.saveGState()
            let pageRect = CGRect(x: (cell.minX + sheet.offsetX) * pointsPerMM,
                                  y: pageSize.height - (cell.maxY + sheet.offsetY) * pointsPerMM,
                                  width: cell.width * pointsPerMM, height: cell.height * pointsPerMM)
            cg.clip(to: pageRect)
            cg.translateBy(x: pageRect.minX, y: pageRect.minY)
            var label = document; label.sheet = nil; label.items = sheet.labels[index]
            try LabelRenderer.draw(label, in: cg, height: pageRect.height,
                                   resolution: 72.0 / 180, smooth: true, color: true)
            cg.restoreGState()
        }
        if sheet.plainPaper && sheet.cutLines && sheet.template.count > 1 {
            // One path per shared edge avoids dark double strokes between adjacent labels.
            cg.saveGState()
            cg.translateBy(x: sheet.offsetX * pointsPerMM, y: -sheet.offsetY * pointsPerMM)
            cg.setStrokeColor(NSColor(white: 0.72, alpha: 1).cgColor)
            cg.setLineWidth(0.35); cg.setLineDash(phase: 0, lengths: [2, 2])
            let template = sheet.template
            let left = template.left * pointsPerMM
            let right = (template.left + Double(template.columns) * template.width) * pointsPerMM
            let top = pageSize.height - template.top * pointsPerMM
            let bottom = top - Double(template.rows) * template.height * pointsPerMM
            for column in 0...template.columns {
                let x = left + Double(column) * template.width * pointsPerMM
                cg.move(to: CGPoint(x: x, y: bottom)); cg.addLine(to: CGPoint(x: x, y: top))
            }
            for row in 0...template.rows {
                let y = top - Double(row) * template.height * pointsPerMM
                cg.move(to: CGPoint(x: left, y: y)); cg.addLine(to: CGPoint(x: right, y: y))
            }
            cg.strokePath(); cg.restoreGState()
        }
        cg.endPDFPage(); cg.closePDF()
        return data as Data
    }

    static func preview(_ data: Data) throws -> CGImage {
        guard let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) else { throw RenderError.failed("Could not read A4 PDF") }
        let image = withExtendedLifetime(pdf) {
            page.thumbnail(of: CGSize(width: 840, height: 1188), for: .mediaBox)
        }
        guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw RenderError.failed("Could not preview A4 PDF")
        }
        return bitmap
    }
}

@MainActor final class SheetPrintView: NSView {
    private let pdf: PDFDocument
    private let page: PDFPage
    override var isFlipped: Bool { false }
    init(data: Data) throws {
        guard let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) else { throw RenderError.failed("Invalid print PDF") }
        self.pdf = pdf; self.page = page
        super.init(frame: CGRect(origin: .zero, size: SheetRenderer.pageSize))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func knowsPageRange(_ range: NSRangePointer) -> Bool { range.pointee = NSRange(location: 1, length: 1); return true }
    override func rectForPage(_ page: Int) -> NSRect { bounds }
    override func locationOfPrintRect(_ rect: NSRect) -> NSPoint {
        // AppKit's default adds the printer's imageable margins. Anchor to the
        // physical paper instead, and account for driver rounding of A4 height.
        let paperHeight = NSPrintOperation.current?.printInfo.paperSize.height ?? bounds.height
        return NSPoint(x: 0, y: paperHeight - rect.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        page.draw(with: .mediaBox, to: cg)
    }
}

@MainActor enum SheetPrintSettings {
    static func make(printerName: String?, copies: Int = 1) -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        if let printerName, let printer = NSPrinter(name: printerName) { info.printer = printer }
        info.paperSize = SheetRenderer.pageSize; info.orientation = .portrait
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        info.horizontalPagination = .clip; info.verticalPagination = .clip
        info.scalingFactor = 1
        info.dictionary()[NSPrintInfo.AttributeKey.copies] = copies
        return info
    }
}
