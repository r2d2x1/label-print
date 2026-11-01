import Foundation
import AppKit

public enum ItemKind: String, Codable, CaseIterable, Sendable { case text, qr, image, icon }
public struct LabelItem: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var kind: ItemKind
    public var content: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var fontName: String? = nil
    public var fontSize: Double = 10
    public var autoFitText: Bool? = nil
    public var lockAspectRatio: Bool? = nil
    public var bold = false
    public var italic = false
    public var alignment = "left"
    public var imageData: Data? = nil
    public init(kind: ItemKind, content: String, x: Double, y: Double, width: Double, height: Double) {
        self.kind = kind; self.content = content; self.x = x; self.y = y
        self.width = width; self.height = height
    }
}

public extension LabelItem {
    /// Shared font resolution for editing, text measurement, and printing.
    /// Missing fontName keeps older saved labels on the system font.
    func resolvedFont(ofSize size: Double) -> NSFont {
        let manager = NSFontManager.shared
        var font: NSFont
        if let family = fontName, family != "System", !family.isEmpty {
            font = manager.font(withFamily: family, traits: [], weight: 5, size: size)
                ?? NSFont(name: family, size: size)
                ?? NSFont.systemFont(ofSize: size)
            if bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        } else {
            font = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
        return italic ? manager.convert(font, toHaveTrait: .italicFontMask) : font
    }
    var keepsAspectRatio: Bool { kind == .image && (lockAspectRatio ?? false) }

    mutating func resizeImage(width proposedWidth: Double? = nil, height proposedHeight: Double? = nil,
                              maxWidth: Double, maxHeight: Double) {
        guard keepsAspectRatio, width > 0, height > 0 else { return }
        let requested = proposedWidth.map { $0 / width } ?? proposedHeight.map { $0 / height } ?? 1
        guard requested.isFinite else { return }
        let minimum = max(0.5 / width, 0.5 / height)
        let maximum = min(maxWidth / width, maxHeight / height)
        guard minimum <= maximum else { return }
        let factor = min(maximum, max(minimum, requested))
        width *= factor; height *= factor
    }

    var automaticallyFitsText: Bool { autoFitText ?? false }

    /// Fit complete lines using the same font metrics as the print renderer.
    mutating func fitTextToBox(constrainWidth: Bool = true) {
        guard kind == .text, automaticallyFitsText, !content.isEmpty else { return }
        let availableWidth = max(0.1, width * 72 / 25.4 - 0.8)
        let availableHeight = max(0.1, height * 72 / 25.4 - 0.8)
        func fits(_ size: Double) -> Bool {
            let font = resolvedFont(ofSize: size)
            let bounds = (content as NSString).boundingRect(
                with: NSSize(width: 1_000_000, height: 1_000_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
            let lineHeight = font.ascender - font.descender + font.leading
            return (!constrainWidth || bounds.width <= availableWidth)
                && max(bounds.height, lineHeight) <= availableHeight
        }
        var lower = 1.0, upper = 200.0
        for _ in 0..<20 {
            let middle = (lower + upper) / 2
            if fits(middle) { lower = middle } else { upper = middle }
        }
        fontSize = (lower * 100).rounded(.down) / 100
    }

    var printFont: NSFont { resolvedFont(ofSize: fontSize * 180 / 72) }
    var naturalTextWidthMM: Double {
        let longest = content.components(separatedBy: .newlines).map {
            ($0 as NSString).size(withAttributes: [.font: printFont]).width
        }.max() ?? 0
        // Round to printer dots, with two dots for glyph overhang and rounding.
        return max(0.5, (ceil(longest) + 2) * 25.4 / 180)
    }
}

public struct LabelDocument: Codable, Equatable, Sendable {
    /// PT-2430PC minimum finished label length (one inch).
    public static let minimumLengthMM = 25.4
    public var version = 1
    public var name = "Storage Box A"
    public var tapeMM: Double = 12
    public var lengthMM: Double = 60
    public var autoLength = true
    public var marginMM: Double = 2
    public var items: [LabelItem] = []
    public var sheet: SheetLayout? = nil
    public init() {}
    public static var blank: LabelDocument {
        var doc = LabelDocument()
        doc.name = "Untitled Label"; doc.lengthMM = 40; doc.autoLength = false
        return doc
    }
    public static var sample: LabelDocument {
        var doc = LabelDocument()
        var heading = LabelItem(kind: .text, content: "Storage Box A", x: 17, y: 1.5, width: 40, height: 4.5)
        heading.fontSize = 10; heading.bold = true
        var subtitle = LabelItem(kind: .text, content: "Electronics", x: 17, y: 6, width: 40, height: 4)
        subtitle.fontSize = 8
        doc.items = [LabelItem(kind: .qr, content: "https://example.com/box-a", x: 3, y: 1, width: 10, height: 10), heading, subtitle]
        return doc
    }
    /// Fit text to its measured lines rather than its possibly oversized box.
    public func itemWidthMM(_ item: LabelItem) -> Double {
        autoLength && item.kind == .text ? min(1000 - item.x, item.naturalTextWidthMM) : item.width
    }
    public var contentLengthMM: Double {
        max(Self.minimumLengthMM, min(1000, (items.map { item in
            item.x + (item.kind == .text ? item.naturalTextWidthMM : item.width)
        }.max() ?? 0) + marginMM))
    }
    public var effectiveLengthMM: Double { sheet != nil ? lengthMM : autoLength ? contentLengthMM : max(Self.minimumLengthMM, lengthMM) }
    /// Expand older short documents symmetrically; never shift just the print
    /// stream, which would make the editable preview disagree with output.
    public func normalizingMinimumLength() -> LabelDocument {
        guard sheet == nil else { return self }
        let oldLength = autoLength ? max(20, min(1000, (items.map {
            $0.x + ($0.kind == .text ? $0.naturalTextWidthMM : $0.width)
        }.max() ?? 0) + marginMM)) : lengthMM
        guard oldLength < Self.minimumLengthMM else { return self }
        var result = self
        for index in result.items.indices {
            if autoLength && result.items[index].kind == .text {
                result.items[index].width = itemWidthMM(result.items[index])
            }
            result.items[index].x += (Self.minimumLengthMM - oldLength) / 2
        }
        result.lengthMM = Self.minimumLengthMM; result.autoLength = false
        return result
    }
    public var pixelWidth: Int { Self.dots(effectiveLengthMM) }
    public var pixelHeight: Int { Self.dots(tapeMM) }
    public static func dots(_ mm: Double) -> Int { Int((mm * 180 / 25.4).rounded()) }
    public static func printableDots(_ tape: Double) -> Int {
        switch tape { case 6: return 32; case 9: return 52; case 12: return 76; case 18: return 120; case 24: return 128; default: return 0 }
    }
    public var printableInsetMM: Double {
        if sheet != nil { return 0 }
        return Double((pixelHeight - Self.printableDots(tapeMM)) / 2) * 25.4 / 180
    }
    public var printableHeightMM: Double { sheet != nil ? tapeMM : Double(Self.printableDots(tapeMM)) * 25.4 / 180 }
    public var printableBottomMM: Double { printableInsetMM + printableHeightMM }
    public func validated() throws -> LabelDocument {
        guard version == 1, lengthMM.isFinite, marginMM.isFinite,
              (0...20).contains(marginMM), items.count <= 500 else { throw DocumentError.invalid }
        if let sheet {
            try sheet.validated()
            guard !autoLength, lengthMM == sheet.template.width, tapeMM == sheet.template.height,
                  items == sheet.labels[sheet.activeIndex] else { throw DocumentError.invalid }
            try validateItems(width: lengthMM, height: tapeMM)
        } else {
            guard [6.0, 9, 12, 18, 24].contains(tapeMM), (20...1000).contains(lengthMM) else { throw DocumentError.invalid }
            try validateItems(width: 1000, height: tapeMM)
        }
        return self
    }
    public func validateItems(width: Double, height: Double) throws {
        guard items.count <= 500, Set(items.map(\.id)).count == items.count else { throw DocumentError.invalid }
        for i in items {
            guard [i.x, i.y, i.width, i.height, i.fontSize].allSatisfy(\.isFinite),
                  i.x >= 0, i.y >= 0, i.width >= 0.5, i.height >= 0.5,
                  i.x + i.width <= width + 0.001, i.y + i.height <= height + 0.001,
                  (1...200).contains(i.fontSize), (i.fontName?.count ?? 0) <= 200, i.content.count <= 10000,
                  (i.imageData?.count ?? 0) <= 20_000_000 else { throw DocumentError.invalid }
        }
    }
    public mutating func syncActiveLabel() {
        if let index = sheet?.activeIndex, sheet!.labels.indices.contains(index) { sheet!.labels[index] = items }
    }

}
public enum DocumentError: LocalizedError {
    case invalid
    public var errorDescription: String? { "Invalid label file. Check its version, dimensions, and item data." }
}

public struct RulerTick: Equatable {
    public let mm: Int
    public var isMajor: Bool { mm % 10 == 0 }
    public var isMedium: Bool { mm % 5 == 0 }
    public static func ticks(length: Double) -> [RulerTick] {
        guard length.isFinite, length >= 0, length <= 1000 else { return [] }
        return (0...Int(length.rounded(.down))).map { RulerTick(mm: $0) }
    }
}

public struct DocumentHistory {
    private var past: [LabelDocument] = []
    private var future: [LabelDocument] = []
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public mutating func record(_ document: LabelDocument) {
        past.append(document); if past.count > 100 { past.removeFirst() }; future.removeAll()
    }
    public mutating func undo(_ current: LabelDocument) -> LabelDocument? {
        guard let previous = past.popLast() else { return nil }; future.append(current); return previous
    }
    public mutating func redo(_ current: LabelDocument) -> LabelDocument? {
        guard let next = future.popLast() else { return nil }; past.append(current); return next
    }
}
