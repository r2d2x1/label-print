import AppKit
import UniformTypeIdentifiers

/// Reads a copied bitmap (screenshots, Preview, browsers) or a copied local
/// image file. Test callers use a private pasteboard, never the user's clipboard.
enum ClipboardImages {
    static let maximumBytes = 20_000_000
    // Native clipboard TIFF can be much larger than its compressed PNG.
    static let maximumInputBytes = 100_000_000
    static let types: [NSPasteboard.PasteboardType] = [
        .png, .tiff,
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier),
        NSPasteboard.PasteboardType(UTType.gif.identifier),
        NSPasteboard.PasteboardType(UTType.bmp.identifier), .pdf
    ]
    enum Route { case text, image }
    static func route(_ pasteboard: NSPasteboard, editingText: Bool) -> Route {
        let hasText = pasteboard.availableType(from: [.string, .rtf, .rtfd, .html]) != nil
        if editingText && hasText { return .text }
        return canRead(pasteboard) ? .image : .text
    }
    static func canRead(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: types) != nil || localImageURL(pasteboard) != nil
    }
    static func readPNG(_ pasteboard: NSPasteboard) throws -> Data {
        if let type = pasteboard.availableType(from: types), let data = pasteboard.data(forType: type) {
            return try png(data)
        }
        if let url = localImageURL(pasteboard) {
            let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes <= maximumInputBytes else { throw RenderError.failed("The copied image is too large") }
            return try png(Data(contentsOf: url))
        }
        throw RenderError.failed("The clipboard does not contain an image. Copy an image or screenshot first.")
    }
    private static func localImageURL(_ pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options)?.first as? URL)
    }
    private static func png(_ data: Data) throws -> Data {
        guard data.count <= maximumInputBytes else { throw RenderError.failed("The copied image is too large") }
        return try ImageProcessing.png(data)
    }
}
