import AppKit
import Foundation
import LabelCore

@MainActor enum DragBenchmark {
    static func run() throws {
        _ = NSApplication.shared
        let size = 2048
        var pixels = [UInt8](repeating: 255, count: size * size)
        for y in 0..<size { for x in 0..<size where (x / 32 + y / 32) % 2 == 0 { pixels[y * size + x] = 0 } }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider, decode: nil,
                            shouldInterpolate: false, intent: .defaultIntent)!
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        var imageItem = LabelItem(kind: .image, content: "2048px-checkerboard.png", x: 2, y: 1, width: 10, height: 10)
        imageItem.imageData = png
        for (name, item) in [("text", LabelDocument.sample.items[1]), ("image-2048px", imageItem)] {
            let store = EditorStore(document: .sample)
            store.change { $0.items = [item]; $0.autoLength = false; $0.lengthMM = 60 }
            let original = store.document
            let started = CFAbsoluteTimeGetCurrent()
            var times: [Double] = []
            for step in 0..<120 {
                let tick = CFAbsoluteTimeGetCurrent()
                store.drag(id: item.id, dx: Double(step) / 120 * 8, dy: 0)
                times.append((CFAbsoluteTimeGetCurrent() - tick) * 1000)
            }
            let updateMS = (CFAbsoluteTimeGetCurrent() - started) * 1000
            let beforeCommit = CFAbsoluteTimeGetCurrent()
            store.endGesture()
            let commitMS = (CFAbsoluteTimeGetCurrent() - beforeCommit) * 1000
            times.sort()
            guard store.document.items[0].x > original.items[0].x else { throw RenderError.failed("Drag benchmark did not move item") }
            store.undo()
            guard store.document == original else { throw RenderError.failed("Drag did not undo as one action") }
            print(String(format: "DRAG %@: 120 updates total=%.3f ms; median=%.3f ms; p95=%.3f ms; max=%.3f ms; commit=%.3f ms",
                         name, updateMS, times[times.count / 2], times[Int(Double(times.count - 1) * 0.95)], times.last!, commitMS))
        }
    }
}
