import AppKit

enum ImageProcessing {
    /// Composite transparency onto the white tape, retain gray tones, and trim
    /// only empty (near-white) outer rows/columns. Dark backgrounds are content.
    static func png(_ data: Data, crop: Bool = true) throws -> Data {
        guard let source = NSImage(data: data),
              let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              image.width <= 20_000, image.height <= 20_000,
              image.width * image.height <= 40_000_000 else {
            throw RenderError.failed("Image could not be loaded or exceeds 40 megapixels")
        }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        let output: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return nil }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let gray = context.makeImage() else { return nil }
            guard crop else { return gray }
            let bytes = buffer.bindMemory(to: UInt8.self)
            var left = width, top = height, right = -1, bottom = -1
            for y in 0..<height {
                for x in 0..<width where bytes[y * width + x] < 250 {
                    left = min(left, x); right = max(right, x)
                    top = min(top, y); bottom = max(bottom, y)
                }
            }
            // A blank image has no meaningful content boundary; keep its size.
            guard right >= left, bottom >= top else { return gray }
            return gray.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1))
        }
        guard let output,
              let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]),
              png.count <= ClipboardImages.maximumBytes else {
            throw RenderError.failed("Processed image is too large")
        }
        return png
    }
}
