import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LabelCore

@MainActor final class EditorStore: ObservableObject {
    @Published var document: LabelDocument
    @Published var selectionIDs: Set<UUID> = []
    var selection: UUID? {
        get { selectionIDs.count == 1 ? selectionIDs.first : nil }
        set { selectionIDs = newValue.map { [$0] } ?? [] }
    }
    var selectedItems: [LabelItem] { document.items.filter { selectionIDs.contains($0.id) } }
    func select(_ id: UUID, extending: Bool = false) {
        if extending {
            if selectionIDs.contains(id) { selectionIDs.remove(id) } else { selectionIDs.insert(id) }
        } else { selectionIDs = [id] }
    }
    func alignSelection(_ alignment: ItemAlignment) {
        guard !selectedItems.isEmpty else { return }
        endGesture()
        change { $0.align(selectionIDs, to: alignment) }
    }
    func fitSelectionToLabel() {
        guard !selectedItems.isEmpty else { return }
        endGesture()
        let length = document.effectiveLengthMM
        var items = selectedItems
        for index in items.indices { items[index].width = document.itemWidthMM(items[index]) }
        if items.count == 1, items[0].kind == .image, let data = items[0].imageData,
           let source = NSImage(data: data),
           let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            items[0].width = items[0].height * Double(image.width) / Double(image.height)
        }
        let left = items.map(\.x).min()!, top = items.map(\.y).min()!
        let width = items.map { $0.x + $0.width }.max()! - left
        let height = items.map { $0.y + $0.height }.max()! - top
        var factor = min(length / width, document.printableHeightMM / height)
        for item in items where item.kind == .text { factor = min(factor, 200 / item.fontSize) }
        guard items.allSatisfy({ $0.width * factor >= 0.5 && $0.height * factor >= 0.5 && ($0.kind != .text || $0.fontSize * factor >= 1) }) else {
            message = "Selection cannot fit without making an object too small"; return
        }
        let x = (length - width * factor) / 2
        let y = document.printableInsetMM + (document.printableHeightMM - height * factor) / 2
        change { doc in
            for index in doc.items.indices where doc.autoLength && doc.items[index].kind == .text {
                doc.items[index].width = doc.itemWidthMM(doc.items[index])
            }
            doc.lengthMM = length; doc.autoLength = false
            for var item in items {
                item.x = x + (item.x - left) * factor
                item.y = y + (item.y - top) * factor
                item.width *= factor; item.height *= factor
                if item.kind == .text { item.fontSize = max(1, item.fontSize * factor) }
                if let index = doc.items.firstIndex(where: { $0.id == item.id }) { doc.items[index] = item }
            }
        }
    }
    @Published var snapX: Double?
    @Published var snapY: Double?
    @Published var preview: CGImage?
    @Published var sheetPreview: CGImage?
    @Published var sheetOverview = true
    @Published var printerName = "PT-2430PC"
    @Published var systemPrinters: [String] = EditorStore.a4Printers()
    static func a4Printers() -> [String] {
        NSPrinter.printerNames.filter { name in
            guard !name.localizedCaseInsensitiveContains("PT-2430PC"), let printer = NSPrinter(name: name) else { return false }
            let size = printer.pageSize(forPaper: .init(rawValue: "A4"))
            return abs(size.width - 210 * 72 / 25.4) < 3 && abs(size.height - 297 * 72 / 25.4) < 3
        }
    }
    @Published var copySheet = false
    private var tapeDraft: LabelDocument?
    private var sheetDraft: LabelDocument?
    private var tapeHistory = DocumentHistory()
    private var sheetHistory = DocumentHistory()
    var isA4: Bool { document.sheet != nil }
    @Published var renderError: String?
    @Published var message = "Printer not checked"
    @Published var connected = false
    @Published var busy = false
    @Published var copies = 1
    @Published var cut = true
    @Published var printDots = false
    @Published var fit = true
    @Published var pointsPerMM = 72.0 / 25.4
    @Published var iconPicker = false
    @Published var textEditRequest: UUID?
    @Published var textEditSelectAll = false
    @Published var cropImageItem: LabelItem?
    private var textEditStart: LabelDocument?
    @Published var fileURL: URL?
    @Published var dirty = false
    @Published var history = DocumentHistory()
    private let printer = PrinterService()
    private var rendered: RenderedLabel?
    private var gestureStart: LabelDocument?
    private var gestureIDs: Set<UUID> = []
    private var gestureWidths: [UUID: Double] = [:]
    private(set) var draggedItems: [UUID: LabelItem] = [:]
    private(set) var renderCount = 0
    private(set) var spriteRenderCount = 0
    private(set) var sprites: [UUID: ItemSprite] = [:]
    struct ItemSprite {
        let signature: LabelItem
        let widthMM: Double
        let image: CGImage
        let smoothImage: CGImage
    }
    func itemWidthMM(_ item: LabelItem) -> Double { sprites[item.id]?.widthMM ?? document.itemWidthMM(item) }
    var selected: LabelItem? { document.items.first { $0.id == selection } }
    init(document: LabelDocument = .blank) {
        self.document = document.normalizingMinimumLength()
        selection = document.items.first(where: { $0.kind == .text })?.id; render()
    }
    func render() {
        renderCount += 1
        do {
            let output = document.sheet == nil ? try LabelRenderer.render(document) : nil
            if document.sheet != nil {
                sheetPreview = try SheetRenderer.preview(SheetRenderer.pdf(document, printOnly: false))
            } else { sheetPreview = nil }
            var next: [UUID: ItemSprite] = [:]
            for item in document.items {
                let width = document.itemWidthMM(item)
                var signature = item; signature.x = 0; signature.y = 0; signature.width = width
                if let cached = sprites[item.id], cached.signature == signature, cached.widthMM == width {
                    next[item.id] = cached
                } else {
                    let image = try LabelRenderer.renderSprite(item, widthMM: width, color: isA4)
                    next[item.id] = ItemSprite(signature: signature, widthMM: width, image: image,
                                               smoothImage: try LabelRenderer.renderSprite(item, widthMM: width, smooth: true, color: isA4))
                    spriteRenderCount += 1
                }
            }
            sprites = next; rendered = output; preview = output?.image ?? sheetPreview; renderError = nil
        } catch { sprites = [:]; rendered = nil; preview = nil; renderError = error.localizedDescription }
    }
    func change(_ action: (inout LabelDocument) -> Void) {
        // Native fields may commit an unchanged value after a toolbar action.
        // Such commits must not end a newly requested text-edit session.
        var next = document; action(&next)
        for index in next.items.indices {
            next.items[index].fitTextToBox(constrainWidth: !next.autoLength)
        }
        next.syncActiveLabel()
        guard next != document else { return }
        finishTextEditing()
        history.record(document); document = next; dirty = true; render()
    }
    func edit(_ action: (inout LabelItem) -> Void) {
        guard let index = document.items.firstIndex(where: { $0.id == selection }) else { return }
        change { doc in
            var item = doc.items[index]; action(&item); clamp(&item, in: doc); doc.items[index] = item
        }
    }
    func setDimension(_ key: WritableKeyPath<LabelItem, Double>, value: Double) {
        guard value.isFinite else { return }
        let maxWidth = document.autoLength ? 1000 : document.lengthMM
        let maxHeight = document.tapeMM
        edit { item in
            if item.keepsAspectRatio && (key == \LabelItem.width || key == \LabelItem.height) {
                item.resizeImage(width: key == \LabelItem.width ? value : nil,
                                 height: key == \LabelItem.height ? value : nil,
                                 maxWidth: maxWidth, maxHeight: maxHeight)
            } else { item[keyPath: key] = value }
        }
    }
    private func clamp(_ item: inout LabelItem, in doc: LabelDocument) {
        item.width = max(0.5, min(item.width, doc.autoLength ? 1000 : doc.lengthMM))
        item.height = max(0.5, min(item.height, doc.tapeMM))
        if item.kind == .qr { item.width = min(item.width, item.height); item.height = item.width }
        item.x = max(0, min(item.x, (doc.autoLength ? 1000 : doc.lengthMM) - item.width))
        item.y = max(0, min(item.y, doc.tapeMM - item.height))
        item.fontSize = max(1, min(200, item.fontSize))
        item.fitTextToBox(constrainWidth: !doc.autoLength)
    }
    func setLength(_ value: Double) {
        guard value.isFinite else { return }
        change { doc in
            // Preserve the current fitted text boxes before switching to fixed.
            for index in doc.items.indices where doc.items[index].kind == .text && doc.autoLength {
                doc.items[index].width = doc.itemWidthMM(doc.items[index])
            }
            doc.lengthMM = max(LabelDocument.minimumLengthMM, min(1000, value)); doc.autoLength = false
        }
        if value < LabelDocument.minimumLengthMM { message = "PT-2430PC minimum label length is 25.4 mm" }
    }
    func fitLengthToContent() { change { $0.autoLength = true } }
    func setAutoLength(_ enabled: Bool) {
        if enabled { fitLengthToContent() } else { setLength(document.effectiveLengthMM) }
    }
    func beginTextEditing(_ id: UUID, selectAll: Bool = false) {
        guard document.items.contains(where: { $0.id == id && $0.kind == .text }) else { return }
        finishTextEditing()
        selection = id; textEditSelectAll = selectAll; textEditStart = document; textEditRequest = id
    }
    func finishTextEditing() {
        if let start = textEditStart, start != document { history.record(start) }
        textEditStart = nil; textEditRequest = nil
    }
    func editText(id: UUID, content: String) {
        guard let index = document.items.firstIndex(where: { $0.id == id }) else { return }
        if textEditStart != nil && textEditRequest == id {
            guard document.items[index].content != content else { return }
            document.items[index].content = content
            document.items[index].fitTextToBox(constrainWidth: !document.autoLength)
            document.syncActiveLabel(); dirty = true; render()
        } else { change { $0.items[index].content = content } }
    }
    func resizeTape(_ value: Double) {
        change { doc in
            doc.tapeMM = value
            for index in doc.items.indices {
                var item = doc.items[index]; clamp(&item, in: doc); doc.items[index] = item
            }
        }
    }
    func add(_ kind: ItemKind, content: String = "", data: Data? = nil) {
        if isA4 && sheetOverview { sheetOverview = false; fit = true }
        let inset = document.printableInsetMM + 0.2
        var item = LabelItem(kind: kind, content: content.isEmpty ? (kind == .text ? "New text" : "https://example.com") : content,
            x: 2, y: inset, width: kind == .text ? 30 : 8, height: kind == .text ? 4.5 : 8)
        item.imageData = data; clamp(&item, in: document)
        change { $0.items.append(item) }; selection = item.id
        if kind == .text { beginTextEditing(item.id, selectAll: true) }
    }
    func duplicate() {
        var copies = selectedItems
        guard !copies.isEmpty else { return }
        for index in copies.indices {
            copies[index].id = UUID(); copies[index].x += 2
            clamp(&copies[index], in: document)
        }
        change { $0.items.append(contentsOf: copies) }
        selectionIDs = Set(copies.map(\.id))
    }
    func delete() {
        guard !selectionIDs.isEmpty else { return }
        change { $0.items.removeAll { selectionIDs.contains($0.id) } }; selection = nil
    }
    func undo() {
        finishTextEditing()
        if let doc = history.undo(document) {
            document = doc; selectionIDs.formIntersection(Set(doc.items.map(\.id))); dirty = true; render()
        }
    }
    func redo() {
        finishTextEditing()
        if let doc = history.redo(document) {
            document = doc; selectionIDs.formIntersection(Set(doc.items.map(\.id))); dirty = true; render()
        }
    }
    func beginGesture() { finishTextEditing(); if gestureStart == nil { gestureStart = document } }
    /// Keep all mouse updates transient; selected objects share one bounded
    /// translation so group spacing remains intact at the tape edges.
    @discardableResult func drag(id: UUID, dx: Double, dy: Double, resize: Bool = false, snapToleranceMM: Double = 0, handle: ResizeHandle = .bottomRight) -> LabelItem? {
        beginGesture()
        guard let start = gestureStart, let anchor = start.items.first(where: { $0.id == id }) else { return nil }
        if gestureIDs.isEmpty {
            gestureIDs = !resize && selectionIDs.contains(id) ? selectionIDs : [id]
            gestureWidths = Dictionary(uniqueKeysWithValues: start.items.filter { gestureIDs.contains($0.id) }.map { ($0.id, itemWidthMM($0)) })
        }
        let items = start.items.filter { gestureIDs.contains($0.id) }
        snapX = nil; snapY = nil
        if resize {
            var item = anchor
            let maxLength = start.autoLength ? 1000 : start.lengthMM
            let centerX = anchor.x + anchor.width / 2, centerY = anchor.y + anchor.height / 2
            let maxWidth = handle.horizontal < 0 ? anchor.x + anchor.width : handle.horizontal > 0 ? maxLength - anchor.x : 2 * min(centerX, maxLength - centerX)
            let maxHeight = handle.vertical < 0 ? anchor.y + anchor.height : handle.vertical > 0 ? start.tapeMM - anchor.y : 2 * min(centerY, start.tapeMM - centerY)
            let width = min(maxWidth, max(0.5, anchor.width + dx * handle.horizontal))
            let height = min(maxHeight, max(0.5, anchor.height + dy * handle.vertical))
            if item.keepsAspectRatio || item.kind == .qr {
                let useWidth = handle.vertical == 0 || (handle.horizontal != 0 && abs(dx / anchor.width) >= abs(dy / anchor.height))
                if item.kind == .qr {
                    let side = min(maxWidth, maxHeight, useWidth ? width : height)
                    item.width = side; item.height = side
                } else {
                    item.resizeImage(width: useWidth ? width : nil, height: useWidth ? nil : height,
                                     maxWidth: maxWidth, maxHeight: maxHeight)
                }
            } else { item.width = width; item.height = height }
            if item.kind == .qr { item.width = min(item.width, item.height); item.height = item.width }
            item.x = handle.horizontal < 0 ? anchor.x + anchor.width - item.width : handle.horizontal == 0 ? centerX - item.width / 2 : anchor.x
            item.y = handle.vertical < 0 ? anchor.y + anchor.height - item.height : handle.vertical == 0 ? centerY - item.height / 2 : anchor.y
            clamp(&item, in: start); draggedItems = [id: item]
        } else {
            let maxLength = start.autoLength ? 1000 : start.lengthMM
            let minDX = -(items.map(\.x).min() ?? 0)
            let maxDX = items.map { maxLength - $0.x - (gestureWidths[$0.id] ?? $0.width) }.min() ?? 0
            let minDY = -(items.map(\.y).min() ?? 0)
            let maxDY = items.map { start.tapeMM - $0.y - $0.height }.min() ?? 0
            var boundedDX = max(minDX, min(maxDX, dx)), boundedDY = max(minDY, min(maxDY, dy))
            if snapToleranceMM > 0 && (dx != 0 || dy != 0) {
                let left = items.map(\.x).min()!, right = items.map { $0.x + (gestureWidths[$0.id] ?? $0.width) }.max()!
                let top = items.map(\.y).min()!, bottom = items.map { $0.y + $0.height }.max()!
                let others = start.items.filter { !gestureIDs.contains($0.id) }
                let xs: [Double] = [0, start.effectiveLengthMM / 2, start.effectiveLengthMM] + others.flatMap { [$0.x, $0.x + itemWidthMM($0) / 2, $0.x + itemWidthMM($0)] }
                let ys: [Double] = [0, start.printableInsetMM, start.tapeMM / 2, start.tapeMM - start.printableInsetMM, start.tapeMM] + others.flatMap { [$0.y, $0.y + $0.height / 2, $0.y + $0.height] }
                func snap(_ anchors: [Double], _ targets: [Double], _ delta: Double, _ lower: Double, _ upper: Double) -> (Double, Double?) {
                    var best = delta; var guide: Double?; var distance = snapToleranceMM
                    for target in targets { for anchor in anchors {
                        let candidate = target - anchor
                        let error = abs(candidate - delta)
                        if candidate >= lower && candidate <= upper && error < distance {
                            distance = error; best = candidate; guide = target
                        }
                    } }
                    return (best, guide)
                }
                (boundedDX, snapX) = snap([left, (left + right) / 2, right], xs, boundedDX, minDX, maxDX)
                (boundedDY, snapY) = snap([top, (top + bottom) / 2, bottom], ys, boundedDY, minDY, maxDY)
            }
            draggedItems = Dictionary(uniqueKeysWithValues: items.map { original in
                var item = original
                if start.autoLength && item.kind == .text && (boundedDX != 0 || boundedDY != 0) { item.width = gestureWidths[original.id] ?? original.width }
                item.x += boundedDX; item.y += boundedDY
                return (item.id, item)
            })
        }
        return draggedItems[id]
    }
    func endGesture() {
        finishTextEditing()
        let moved = draggedItems
        gestureStart = nil; gestureIDs = []; gestureWidths = [:]; draggedItems = [:]
        snapX = nil; snapY = nil
        guard document.items.contains(where: { item in moved[item.id].map { $0 != item } ?? false }) else { return }
        change { doc in
            for index in doc.items.indices {
                if let item = moved[doc.items[index].id] { doc.items[index] = item }
            }
        }
    }
    /// Standard paste preserves native text pasting while a text editor is active.
    func paste() {
        let responder = NSApp.keyWindow?.firstResponder
        let textEditing = (responder as? NSTextView)?.isEditable == true
        if ClipboardImages.route(.general, editingText: textEditing) == .image {
            pasteImage()
        } else if !NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) {
            message = "Copy an image first, then paste it onto the label."
        }
    }
    func pasteImage(from pasteboard: NSPasteboard = .general) {
        do {
            let png = try ClipboardImages.readPNG(pasteboard)
            add(.image, content: "Clipboard Image", data: png)
            message = "Pasted grayscale image; blank edges trimmed"
        } catch { message = error.localizedDescription }
    }
    func cropSelectedImage() {
        guard let item = selected, item.kind == .image, let data = item.imageData else { return }
        do {
            let png = try ImageProcessing.png(data)
            guard png != data else { message = "No blank edges to trim"; return }
            edit { $0.imageData = png }
            message = "Image converted to grayscale and blank edges trimmed"
        } catch { message = error.localizedDescription }
    }
    func centerSelectionOnLabel() {
        guard !selectionIDs.isEmpty else { return }
        endGesture()
        change { doc in
            doc.align(selectionIDs, to: .horizontalCenter)
            doc.align(selectionIDs, to: .verticalCenter)
        }
    }
    func focusLabel(_ index: Int, objectID: UUID? = nil, editText: Bool = false) {
        selectLabel(index, focus: true)
        if let objectID, document.items.contains(where: { $0.id == objectID }) { selection = objectID }
        if editText, let item = selected {
            if item.kind == .text { beginTextEditing(item.id) }
            else if item.kind == .image { cropImageItem = item }
        }
    }
    func copyToEmptyLabels() {
        guard let sheet = document.sheet else { return }
        let targets = Set(sheet.labels.indices.filter { $0 != sheet.activeIndex && sheet.labels[$0].isEmpty })
        copyLabel(to: targets)
    }
    func replaceSelectedImage(url: URL? = nil) {
        guard let item = selected, item.kind == .image else { return }
        var source = url
        if source == nil {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK else { return }; source = panel.url
        }
        guard let source else { return }
        do {
            let data = try Data(contentsOf: source)
            guard data.count <= 20_000_000, let image = NSImage(data: data),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]),
                  png.count <= 20_000_000 else { throw RenderError.failed("Choose an image smaller than 20 MB") }
            edit { $0.imageData = png; $0.content = source.lastPathComponent }
            message = "Image replaced; position and frame preserved"
        } catch { message = error.localizedDescription }
    }
    func applyCrop(id: UUID, normalized: CGRect) {
        guard let index = document.items.firstIndex(where: { $0.id == id }), let data = document.items[index].imageData,
              let image = NSImage(data: data), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let unit = normalized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !unit.isNull, unit.width > 0.001, unit.height > 0.001,
              let crop = cg.cropping(to: CGRect(x: unit.minX * Double(cg.width), y: unit.minY * Double(cg.height),
                                               width: unit.width * Double(cg.width), height: unit.height * Double(cg.height)).integral),
              let png = NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:]) else { return }
        change { $0.items[index].imageData = png }
        message = "Image cropped; frame preserved"
    }
    func importImage(url: URL? = nil) {
        var url = url
        if url == nil {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]; panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK else { return }; url = panel.url
        }
        guard let url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 20_000_000, let source = NSImage(data: data) else { throw RenderError.failed("Choose an image smaller than 20 MB") }
            // Normalize import to PNG so saved labels embed portable image data.
            guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]), png.count <= 20_000_000 else {
                throw RenderError.failed("Image is too large")
            }
            add(.image, content: url.lastPathComponent, data: png)
        } catch { message = error.localizedDescription }
    }
    private func confirmDiscard() -> Bool {
        finishTextEditing()
        guard dirty else { return true }
        let alert = NSAlert(); alert.messageText = "Save changes to this label?"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Discard")
        switch alert.runModal() { case .alertFirstButtonReturn: return save(); case .alertThirdButtonReturn: return true; default: return false }
    }
    func canClose() -> Bool { confirmDiscard() }
    func newLabel() {
        guard confirmDiscard() else { return }
        let a4 = isA4
        document = .blank
        if a4 { configureSheet(&document, layout: SheetLayout()) }
        fileURL = nil; dirty = false
        history = DocumentHistory(); selection = nil; render()
    }
    func open() {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 250_000_000 else { throw DocumentError.invalid }
            let doc = try JSONDecoder().decode(LabelDocument.self, from: data).validated()
            document = doc.normalizingMinimumLength(); fileURL = url; dirty = document != doc
            history = DocumentHistory(); selection = nil
            let rememberedPrinter = UserDefaults.standard.string(forKey: "lastA4Printer") ?? "A4 / PDF"
            printerName = document.sheet == nil ? "PT-2430PC" : systemPrinters.contains(rememberedPrinter) ? rememberedPrinter : "A4 / PDF"
            sheetOverview = true; render()
            Task { await refreshPrinter() }
            if dirty { message = "Short label expanded to 25.4 mm with equal padding on both sides. Save to keep the corrected layout." }
        } catch { message = error.localizedDescription }
    }
    @discardableResult func save(as saveAs: Bool = false) -> Bool {
        endGesture()
        var destination: URL? = saveAs ? nil : fileURL
        if destination == nil {
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = document.name + ".label.json"
            guard panel.runModal() == .OK else { return false }; destination = panel.url
        }
        guard let url = destination else { return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document.validated())
            guard data.count <= 250_000_000 else { throw RenderError.failed("Document exceeds 250 MB. Use smaller images before saving.") }
            try data.write(to: url, options: .atomic)
            fileURL = url; dirty = false; message = "Saved \(url.lastPathComponent)"; return true
        } catch { message = error.localizedDescription; return false }
    }
    func export() {
        endGesture()
        if isA4 { exportSheet(); return }
        guard let rendered else { message = renderError ?? "Nothing to export"; return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = document.name + ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try rendered.png().write(to: url, options: .atomic); message = "Exported \(url.lastPathComponent)" }
        catch { message = error.localizedDescription }
    }
    func refreshPrinter() async {
        systemPrinters = Self.a4Printers()
        if isA4 { connected = printerName != "A4 / PDF" && systemPrinters.contains(printerName); message = "A4 · 210 × 297 mm"; return }
        guard !busy else { return }; busy = true; defer { busy = false }
        let checkedPrinter = printerName
        do { let response = try await printer.status()
            guard printerName == checkedPrinter && !isA4 else { return }
            connected = response.ok
            message = response.ok ? "PT-2430PC ready · \(response.tapeMM ?? 0) mm loaded" : response.message
        } catch { connected = false; message = error.localizedDescription }
    }
    func printLabel() async {
        endGesture()
        if isA4 { printSheet(); return }
        guard !busy, let rendered else { return }; busy = true; defer { busy = false }
        let tape = Int(document.tapeMM), copies = copies, cut = cut
        message = "Printing…"
        do {
            let result = try await printer.printLabel(pixels: rendered.pixels, width: rendered.width, height: rendered.height,
                                                       tape: tape, copies: copies, cut: cut)
            message = result.message; if !result.ok { connected = false }
        } catch { connected = false; message = error.localizedDescription }
    }
    func choosePrinter(_ name: String) {
        endGesture()
        let tapePrinter = name.localizedCaseInsensitiveContains("PT-2430PC")
        let switchingMode = tapePrinter == isA4
        if !tapePrinter && !isA4 {
            tapeDraft = document; tapeHistory = history
            history = sheetHistory
            var next = sheetDraft ?? LabelDocument.blank
            if next.sheet == nil { configureSheet(&next, layout: SheetLayout()) }
            document = next
        } else if tapePrinter && isA4 {
            sheetDraft = document; sheetHistory = history
            document = tapeDraft ?? .blank; history = tapeHistory
        }
        printerName = tapePrinter ? "PT-2430PC" : name
        if !tapePrinter && name != "A4 / PDF" { UserDefaults.standard.set(name, forKey: "lastA4Printer") }
        if switchingMode { selection = nil; fit = true; sheetOverview = true; dirty = true }
        render()
        Task { await refreshPrinter() }
    }
    private func configureSheet(_ doc: inout LabelDocument, layout: SheetLayout) {
        doc.sheet = layout; doc.autoLength = false
        doc.lengthMM = layout.template.width; doc.tapeMM = layout.template.height
        doc.items = layout.labels[layout.activeIndex]
    }
    func selectLabel(_ index: Int, focus: Bool = false) {
        let wasOverview = sheetOverview
        endGesture()
        guard let sheet = document.sheet, sheet.labels.indices.contains(index) else { return }
        document.syncActiveLabel()
        document.sheet!.activeIndex = index; document.items = document.sheet!.labels[index]
        selection = document.items.count == 1 ? document.items[0].id : nil; render()
        if focus { sheetOverview = false; if wasOverview { fit = true } }
    }
    func setTemplate(_ id: String) {
        guard let template = SheetTemplate.find(id), id != document.sheet?.templateID else { return }
        endGesture()
        change { doc in
            let previous = doc.sheet
            var next = SheetLayout(templateID: id)
            // Preserve designs by position; undo restores the complete previous layout.
            if let previous {
                for index in 0..<min(previous.labels.count, next.labels.count) {
                    next.labels[index] = previous.labels[index].map { original in
                        var item = original
                        item.width = min(item.width, template.width); item.height = min(item.height, template.height)
                        item.x = min(item.x, template.width - item.width); item.y = min(item.y, template.height - item.height)
                        item.fitTextToBox(); return item
                    }
                }
                next.plainPaper = previous.plainPaper; next.cutLines = previous.cutLines
            }
            configureSheet(&doc, layout: next)
        }
        selection = nil; fit = true; sheetOverview = true
    }
    func editSheet(_ action: (inout SheetLayout) -> Void) {
        endGesture()
        change { doc in if var sheet = doc.sheet { action(&sheet); doc.sheet = sheet } }
    }
    func copyLabel(to targets: Set<Int>) {
        endGesture()
        guard let source = document.sheet?.activeIndex else { return }
        change { doc in doc.sheet?.copyLabel(from: source, to: targets) }
        message = "Copied label \(source + 1) to \(targets.subtracting([source]).count) positions"
    }
    func clearActiveLabel() { endGesture(); change { $0.items = [] }; selection = nil }
    func exportSheet() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = document.name + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try SheetRenderer.pdf(document).write(to: url, options: .atomic); message = "Exported \(url.lastPathComponent)" }
        catch { message = error.localizedDescription }
    }
    func printSheet() {
        guard !busy, let sheet = document.sheet else { return }
        guard !sheet.printPositions.isEmpty else { message = "Select at least one print position"; return }
        do {
            let data = try SheetRenderer.pdf(document)
            let view = try SheetPrintView(data: data)
            let info = SheetPrintSettings.make(printerName: printerName, copies: copies)
            let operation = NSPrintOperation(view: view, printInfo: info)
            operation.showsPrintPanel = true; operation.showsProgressPanel = true
            operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling])
            if operation.run() {
                message = operation.printInfo.jobDisposition == .save ? "PDF file saved" : "A4 print job submitted"
            } else { message = "Printing cancelled" }
        } catch { message = error.localizedDescription }
    }

}
