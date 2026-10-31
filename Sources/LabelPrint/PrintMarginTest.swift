import Foundation
import LabelCore

/// Explicit hardware acceptance command; never invoked by the automated suite.
@MainActor enum PrintMarginTest {
    static func run() async throws {
        var doc = LabelDocument(); doc.autoLength = false; doc.lengthMM = 40
        var heading = LabelItem(kind: .text, content: "40 mm test", x: 10, y: 2, width: 28, height: 4)
        heading.fontSize = 8; heading.bold = true
        var subtitle = LabelItem(kind: .text, content: "Feed 0", x: 10, y: 6, width: 28, height: 3)
        subtitle.fontSize = 6
        doc.items = [LabelItem(kind: .icon, content: "shippingbox", x: 2, y: 2, width: 6, height: 6), heading, subtitle]
        let bitmap = try LabelRenderer.render(doc)
        let service = PrinterService()
        let status = try await service.status()
        guard status.ok, status.tapeMM == 12 else { throw RenderError.failed("Margin test requires a ready PT-2430PC with 12 mm tape: \(status.message)") }
        let result = try await service.printLabel(pixels: bitmap.pixels, width: bitmap.width, height: bitmap.height,
                                                  tape: 12, copies: 1, cut: true)
        guard result.ok else { throw RenderError.failed(result.message) }
        try FileManager.default.createDirectory(atPath: ".build/test-artifacts", withIntermediateDirectories: true)
        try bitmap.png().write(to: URL(fileURLWithPath: ".build/test-artifacts/margin-test-40mm-feed0.png"))
        print("HARDWARE: \(result.message); 40 × 12 mm design, \(bitmap.width) raster columns, pre-cut enabled, firmware feed margin explicitly 0 dots. Inspect/measure the cut label to confirm physical length and leader separation.")
    }
}
