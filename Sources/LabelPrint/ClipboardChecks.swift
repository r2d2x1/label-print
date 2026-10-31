import AppKit
import Foundation
import LabelCore

@MainActor enum ClipboardChecks {
    static func run() throws {
        try checkProcessing()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let fixture = try LabelRenderer.render(.sample)
        let png = try fixture.png()
        board.clearContents(); board.setData(png, forType: .png)
        let changes = board.changeCount
        guard ClipboardImages.canRead(board), ClipboardImages.route(board, editingText: false) == .image else {
            throw RenderError.failed("Clipboard PNG was not detected")
        }
        let store = EditorStore(document: .sample); let original = store.document
        store.pasteImage(from: board)
        guard store.document.items.count == original.items.count + 1,
              store.selected?.kind == .image, let embedded = store.selected?.imageData,
              NSImage(data: embedded) != nil, store.renderError == nil, board.changeCount == changes else {
            throw RenderError.failed("Pasted image was not inserted/rendered or clipboard was changed")
        }
        let pasted = store.document
        guard try JSONDecoder().decode(LabelDocument.self, from: JSONEncoder().encode(pasted)) == pasted else {
            throw RenderError.failed("Pasted image did not persist")
        }
        store.undo(); guard store.document == original else { throw RenderError.failed("Paste image undo failed") }
        store.redo(); guard store.document == pasted else { throw RenderError.failed("Paste image redo failed") }
        board.setString("Copied text", forType: .string)
        guard ClipboardImages.route(board, editingText: true) == .text,
              ClipboardImages.route(board, editingText: false) == .image else {
            throw RenderError.failed("Image paste intercepted text editing")
        }
        board.clearContents(); board.setString("Text only", forType: .string)
        guard !ClipboardImages.canRead(board), ClipboardImages.route(board, editingText: true) == .text else {
            throw RenderError.failed("Text-only clipboard was treated as image")
        }
        let beforeFailure = store.document
        store.pasteImage(from: board)
        guard store.document == beforeFailure else { throw RenderError.failed("Unsupported paste changed the label") }
        board.clearContents(); board.setData(Data([0, 1, 2]), forType: .png)
        store.pasteImage(from: board)
        guard store.document == beforeFailure else { throw RenderError.failed("Corrupt clipboard image changed the label") }
        let tiff = NSBitmapImageRep(cgImage: fixture.image).representation(using: .tiff, properties: [:])!
        board.clearContents(); board.setData(tiff, forType: .tiff)
        guard NSImage(data: try ClipboardImages.readPNG(board)) != nil else { throw RenderError.failed("Clipboard TIFF conversion failed") }
        // A typical uncompressed clipboard photo can exceed the saved-image
        // limit even though its normalized PNG is small. Do not reject it early.
        let side = 2400
        let bytes = Data(repeating: 255, count: side * side * 4)
        let provider = CGDataProvider(data: bytes as CFData)!
        let large = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let largeTIFF = NSBitmapImageRep(cgImage: large).representation(using: .tiff, properties: [:])!
        guard largeTIFF.count > ClipboardImages.maximumBytes else { throw RenderError.failed("Large TIFF fixture was unexpectedly compressed") }
        board.clearContents(); board.setData(largeTIFF, forType: .tiff)
        guard try ClipboardImages.readPNG(board).count <= ClipboardImages.maximumBytes else {
            throw RenderError.failed("Clipboard photo normalization failed")
        }
        try FileManager.default.createDirectory(atPath: ".build/test-artifacts", withIntermediateDirectories: true)
        let file = URL(fileURLWithPath: ".build/test-artifacts/clipboard-image-fixture.png").standardizedFileURL
        try png.write(to: file)
        board.clearContents(); board.writeObjects([file as NSURL])
        guard ClipboardImages.canRead(board), NSImage(data: try ClipboardImages.readPNG(board)) != nil else {
            throw RenderError.failed("Copied local image file was not accepted")
        }
        print("PASS: private-clipboard PNG/TIFF/local image paste, native text routing, embedded save/load, undo/redo, corrupt/unsupported input, clipboard preservation")
    }
    private static func checkProcessing() throws {
        // Unequal margins catch off-by-one and vertically inverted crop bounds.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 10,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<10 { for x in 0..<12 {
            bitmap.setColor(NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1), atX: x, y: y)
        } }
        for y in 2..<7 { for x in 3..<9 {
            bitmap.setColor(NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y)
        } }
        let data = bitmap.representation(using: .png, properties: [:])!
        let result = NSBitmapImageRep(data: try ImageProcessing.png(data))!
        guard result.pixelsWide == 6, result.pixelsHigh == 5 else {
            throw RenderError.failed("White border crop dimensions are incorrect")
        }
        let color = result.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
        guard abs(color.redComponent - color.greenComponent) < 0.001,
              abs(color.greenComponent - color.blueComponent) < 0.001,
              color.redComponent > 0, color.redComponent < 1 else {
            throw RenderError.failed("Image conversion did not retain grayscale tones")
        }
        let screened = try LabelRenderer.halftone(result.cgImage!, width: 32, height: 32)
        let screenedBytes = Array(screened.dataProvider!.data! as Data)
        let ink = screenedBytes.filter { $0 == 0 }.count
        guard ink > 0, ink < screenedBytes.count,
              Set(screenedBytes).isSubset(of: [0, 255]) else {
            throw RenderError.failed("Colored image lost its gray tones in monochrome output")
        }
        var densities: [Int] = []
        for level: UInt8 in [0, 80, 160, 255] {
            let provider = CGDataProvider(data: Data(repeating: level, count: 32 * 32) as CFData)!
            let gray = CGImage(width: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 8,
                               bytesPerRow: 32, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let output = try LabelRenderer.halftone(gray, width: 32, height: 32)
            densities.append(Array(output.dataProvider!.data! as Data).filter { $0 == 0 }.count)
        }
        guard densities[0] == 1024, densities[3] == 0,
              densities[0] > densities[1], densities[1] > densities[2], densities[2] > densities[3] else {
            throw RenderError.failed("Halftone does not preserve black, white and relative gray density")
        }
        print("PASS: colored artwork retains gray halftones; black/white and error-diffused gray densities preserved")
        let uncropped = NSBitmapImageRep(data: try ImageProcessing.png(data, crop: false))!
        guard uncropped.pixelsWide == 12, uncropped.pixelsHigh == 10 else {
            throw RenderError.failed("Grayscale-only processing changed dimensions")
        }
        for y in 0..<10 { for x in 0..<12 where x < 3 || x >= 9 || y < 2 || y >= 7 {
            bitmap.setColor(NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
        } }
        let transparent = NSBitmapImageRep(data: try ImageProcessing.png(bitmap.representation(using: .png, properties: [:])!))!
        guard transparent.pixelsWide == 6, transparent.pixelsHigh == 5 else {
            throw RenderError.failed("Transparent border crop failed")
        }
        let store = EditorStore(document: .sample)
        store.add(.image, content: "Crop fixture", data: data)
        let before = store.document
        store.cropSelectedImage()
        guard store.selected?.imageData != data, store.selected?.x == before.items.last?.x else {
            throw RenderError.failed("Existing image crop failed")
        }
        store.undo()
        guard store.document == before else { throw RenderError.failed("Crop undo failed") }
        print("PASS: grayscale tones, white/transparent border crop, crop dimensions, existing-image crop and undo")
    }
}
