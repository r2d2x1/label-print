import AppKit
import CoreImage
import LabelCore

struct RenderedLabel {
    let image: CGImage
    let pixels: [UInt8]
    let width: Int
    let height: Int
    func png() throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw RenderError.failed("Could not encode PNG")
        }
        return data
    }
}
enum RenderError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case let .failed(message) = self { return message }; return nil }
}

// Shared monochrome rendering for canvas, PNG export, and USB printing.
enum LabelRenderer {
    static let ci = CIContext()
    static func render(_ document: LabelDocument) throws -> RenderedLabel {
        _ = try document.validated()
        let w = document.pixelWidth, h = document.pixelHeight
        var gray = [UInt8](repeating: 255, count: w * h)
        let ok = try gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let cg = CGContext(data: buffer.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            cg.setFillColor(gray: 1, alpha: 1); cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            try draw(document, in: cg, height: h)
            return true
        }
        guard ok else { throw RenderError.failed("Could not create label bitmap") }
        gray = gray.map { $0 < 160 ? 0 : 255 }
        guard let provider = CGDataProvider(data: Data(gray) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8,
                  bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw RenderError.failed("Could not create preview")
        }
        return RenderedLabel(image: image, pixels: gray, width: w, height: h)
    }
    /// Cache a transparent, monochrome item layer. During dragging the canvas
    /// moves these layers using transforms instead of decoding/rasterizing again.
    static func renderSprite(_ item: LabelItem, widthMM: Double, smooth: Bool = false) throws -> CGImage {
        let resolution = smooth ? min(4.0, max(1.0, sqrt(4_000_000 / max(1, widthMM * item.height * pow(180.0 / 25.4, 2))))) : 1
        let scale = 180.0 / 25.4 * resolution
        let width = max(1, Int(ceil(widthMM * scale)))
        let height = max(1, Int(ceil(item.height * scale)))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let cg = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw RenderError.failed("Could not create item preview")
            }
            cg.clear(CGRect(x: 0, y: 0, width: width, height: height))
            var local = item; local.x = 0; local.y = 0; local.width = widthMM
            var doc = LabelDocument(); doc.autoLength = false; doc.items = [local]
            try draw(doc, in: cg, height: height, resolution: resolution, smooth: smooth)
        }
        for offset in stride(from: 0, to: smooth ? 0 : pixels.count, by: 4) {
            let alpha = Int(pixels[offset + 3])
            guard alpha > 0 else { continue }
            let gray = (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
            let mono: UInt8 = gray * 255 < 160 * alpha ? 0 : UInt8(alpha)
            pixels[offset] = mono; pixels[offset + 1] = mono; pixels[offset + 2] = mono
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw RenderError.failed("Could not create item preview image")
        }
        return image
    }
    private static func draw(_ document: LabelDocument, in cg: CGContext, height h: Int, resolution: Double = 1, smooth: Bool = false) throws {
            cg.translateBy(x: 0, y: CGFloat(h)); cg.scaleBy(x: 1, y: -1)
            cg.setShouldAntialias(true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
            defer { NSGraphicsContext.restoreGraphicsState() }
            let scale = 180.0 / 25.4 * resolution
            for item in document.items {
                let rect = CGRect(x: item.x * scale, y: item.y * scale,
                                  width: document.itemWidthMM(item) * scale, height: item.height * scale)
                cg.saveGState(); cg.clip(to: rect)
                switch item.kind {
                case .text:
                    let styled = item.resolvedFont(ofSize: item.printFont.pointSize * resolution)
                    let para = NSMutableParagraphStyle()
                    para.alignment = item.alignment == "center" ? .center : item.alignment == "right" ? .right : .left
                    (item.content as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: styled, .foregroundColor: NSColor.black, .paragraphStyle: para])
                case .qr:
                    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw RenderError.failed("QR generator unavailable") }
                    filter.setValue(Data(item.content.utf8), forKey: "inputMessage")
                    filter.setValue("M", forKey: "inputCorrectionLevel")
                    guard let qr = filter.outputImage, let image = ci.createCGImage(qr, from: qr.extent) else {
                        throw RenderError.failed("QR content is too long")
                    }
                    // Four modules of quiet zone on every side; integer dots/module.
                    let modules = image.width
                    let factor = Int(min(rect.width, rect.height)) / (modules + 8)
                    guard factor >= 1 else { throw RenderError.failed("QR box is too small for its content. Enlarge it or shorten the content.") }
                    let total = CGFloat((modules + 8) * factor)
                    let quiet = CGFloat(4 * factor)
                    let left = (rect.midX - total / 2 + quiet).rounded()
                    let top = (rect.midY - total / 2 + quiet).rounded()
                    let side = CGFloat(modules * factor)
                    let target = CGRect(x: left, y: top, width: side, height: side)
                    cg.setFillColor(gray: 1, alpha: 1); cg.fill(rect)
                    draw(image, in: target, context: cg, interpolate: false)
                case .image:
                    guard let data = item.imageData, let image = NSImage(data: data),
                          let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        throw RenderError.failed("An image could not be loaded")
                    }
                    let target = aspectFit(bitmap, rect)
                    let halftone = try halftone(bitmap, width: max(1, Int(target.width.rounded())),
                                                height: max(1, Int(target.height.rounded())), quantize: !smooth)
                    draw(halftone, in: target, context: cg, interpolate: false)
                case .icon:
                    guard let symbol = NSImage(systemSymbolName: item.content, accessibilityDescription: nil)?
                        .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.black])) else {
                        throw RenderError.failed("Unknown icon: \(item.content)")
                    }
                    // Resolve template/vector symbols in a color bitmap first.
                    // Drawing a template directly into a grayscale context can be blank.
                    let size = NSSize(width: 128, height: 128)
                    let rasterized = NSImage(size: size, flipped: false) { area in
                        symbol.draw(in: area, from: .zero, operation: .sourceOver, fraction: 1)
                        return true
                    }
                    guard let bitmap = rasterized.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        throw RenderError.failed("Could not render icon")
                    }
                    draw(bitmap, in: aspectFit(bitmap, rect), context: cg, interpolate: true)
                }
                cg.restoreGState()
            }
    }
    private static func aspectFit(_ image: CGImage, _ rect: CGRect) -> CGRect {
        let factor = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        return CGRect(x: rect.midX - CGFloat(image.width) * factor / 2, y: rect.midY - CGFloat(image.height) * factor / 2,
                      width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
    }
    /// Resize once at printer resolution, then diffuse quantization error.
    /// Serpentine scanning avoids the repeating blocks of ordered screening.
    static func halftone(_ image: CGImage, width: Int, height: Int, quantize: Bool = true) throws -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else {
                throw RenderError.failed("Could not process image tones")
            }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        if quantize {
            var current = [Double](repeating: 0, count: width + 2)
            var next = current
            for y in 0..<height {
                let direction = y % 2 == 0 ? 1 : -1
                for step in 0..<width {
                    let x = direction == 1 ? step : width - 1 - step
                    let index = y * width + x
                    let source = pixels[index]
                    // Keep pure white/black artwork exact, especially fine lines.
                    let value = source == 0 || source == 255 ? Double(source) : min(255, max(0, Double(source) + current[x + 1]))
                    let output: UInt8 = value < 128 ? 0 : 255
                    pixels[index] = output
                    let error = value - Double(output)
                    current[x + 1 + direction] += error * 7 / 16
                    next[x + 1 - direction] += error * 3 / 16
                    next[x + 1] += error * 5 / 16
                    next[x + 1 + direction] += error / 16
                }
                current = next
                next = [Double](repeating: 0, count: width + 2)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let result = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                   bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw RenderError.failed("Could not create image halftone")
        }
        return result
    }
    private static func draw(_ image: CGImage, in rect: CGRect, context: CGContext, interpolate: Bool) {
        context.saveGState(); context.interpolationQuality = interpolate ? .high : .none
        context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size)); context.restoreGState()
    }
}
