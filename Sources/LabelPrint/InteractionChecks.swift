import AppKit
import LabelCore

@MainActor enum InteractionChecks {
    static func run() throws {
        _ = NSApplication.shared
        let store = EditorStore()
        store.add(.text)
        guard let item = store.selected, store.textEditRequest == item.id, store.textEditSelectAll else {
            throw RenderError.failed("New text did not request immediate input")
        }
        store.change { $0.name = $0.name }
        guard store.textEditRequest == item.id else { throw RenderError.failed("No-op field commit interrupted text input") }
        store.editText(id: item.id, content: "One")
        store.editText(id: item.id, content: "One completed edit")
        store.finishTextEditing(); store.undo()
        guard store.selected?.content == "New text" else { throw RenderError.failed("Text session was not one undo step") }
        store.redo()
        guard store.selected?.content == "One completed edit" else { throw RenderError.failed("Text session redo failed") }
        let beforeCenter = store.document
        store.centerSelectionOnLabel()
        guard let centered = store.selected,
              abs(centered.x + centered.width / 2 - store.document.effectiveLengthMM / 2) < 0.001,
              abs(centered.y + centered.height / 2 - (store.document.printableInsetMM + store.document.printableBottomMM) / 2) < 0.001 else {
            throw RenderError.failed("One-step label centering failed")
        }
        store.undo(); guard store.document == beforeCenter else { throw RenderError.failed("Center must undo once") }

        var doc = LabelDocument.blank
        let box = LabelItem(kind: .text, content: "Box", x: 5, y: 3, width: 8, height: 4)
        doc.items = [box]
        for handle in ResizeHandle.allCases {
            let editor = EditorStore(document: doc)
            editor.drag(id: box.id, dx: 2, dy: 1, resize: true, handle: handle); editor.endGesture()
            let resized = editor.document.items[0]
            let oldAnchorX = box.x + (handle.horizontal < 0 ? box.width : handle.horizontal == 0 ? box.width / 2 : 0)
            let newAnchorX = resized.x + (handle.horizontal < 0 ? resized.width : handle.horizontal == 0 ? resized.width / 2 : 0)
            let oldAnchorY = box.y + (handle.vertical < 0 ? box.height : handle.vertical == 0 ? box.height / 2 : 0)
            let newAnchorY = resized.y + (handle.vertical < 0 ? resized.height : handle.vertical == 0 ? resized.height / 2 : 0)
            guard abs(oldAnchorX - newAnchorX) < 0.0001, abs(oldAnchorY - newAnchorY) < 0.0001 else {
                throw RenderError.failed("Resize moved the opposite anchor: \(handle)")
            }
            _ = try editor.document.validated()
            editor.undo(); guard editor.document == doc else { throw RenderError.failed("Resize undo failed") }
        }

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<20 { for x in 0..<40 {
            bitmap.setColor(NSColor(calibratedRed: y < 10 ? 1 : 0, green: 0, blue: y < 10 ? 0 : 1, alpha: 1), atX: x, y: y)
        } }
        let png = bitmap.representation(using: .png, properties: [:])!
        var image = LabelItem(kind: .image, content: "original.png", x: 5, y: 3, width: 8, height: 4)
        image.imageData = png; image.lockAspectRatio = true
        doc.items = [image]
        let images = EditorStore(document: doc); images.selection = image.id
        try FileManager.default.createDirectory(atPath: ".build/test-artifacts", withIntermediateDirectories: true)
        let replacement = URL(fileURLWithPath: ".build/test-artifacts/replacement-fixture.png")
        try png.write(to: replacement)
        images.replaceSelectedImage(url: replacement)
        guard let replaced = images.selected, replaced.id == image.id, replaced.x == image.x,
              replaced.y == image.y, replaced.width == image.width, replaced.height == image.height,
              replaced.keepsAspectRatio else { throw RenderError.failed("Replacement lost frame or ratio lock") }
        images.undo(); guard images.document == doc else { throw RenderError.failed("Replacement undo failed") }
        images.applyCrop(id: image.id, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        guard let cropped = images.selected, let croppedData = cropped.imageData,
              let cropBitmap = NSBitmapImageRep(data: croppedData), cropBitmap.pixelsWide == 20,
              cropBitmap.pixelsHigh == 10, cropped.width == image.width, cropped.height == image.height else {
            throw RenderError.failed("Crop lost dimensions or label frame")
        }
        let topColor = cropBitmap.colorAt(x: 1, y: 1)!.usingColorSpace(.deviceRGB)!
        guard topColor.redComponent > 0.9, topColor.blueComponent < 0.1 else { throw RenderError.failed("Crop was vertically inverted") }
        images.undo(); guard images.document == doc else { throw RenderError.failed("Crop undo failed") }
        images.drag(id: image.id, dx: 2, dy: 0, resize: true, handle: .right); images.endGesture()
        guard let side = images.selected, abs(side.width / side.height - 2) < 0.001,
              abs(side.y + side.height / 2 - 5) < 0.001 else { throw RenderError.failed("Side resize lost aspect ratio or center") }

        let sheet = EditorStore()
        sheet.choosePrinter("A4 / PDF"); sheet.setTemplate("3475")
        sheet.add(.text, content: "Source"); sheet.finishTextEditing()
        sheet.copyLabel(to: [1])
        sheet.focusLabel(0); sheet.fit = false; sheet.pointsPerMM = 9
        sheet.focusLabel(1)
        guard sheet.selected?.content == "Source", !sheet.fit, sheet.pointsPerMM == 9 else {
            throw RenderError.failed("Label navigation reset zoom or failed to select its sole object")
        }
        sheet.beginTextEditing(sheet.selected!.id)
        sheet.editText(id: sheet.selected!.id, content: "Independent")
        sheet.finishTextEditing(); sheet.copyToEmptyLabels()
        guard sheet.document.sheet!.labels[0][0].content == "Source",
              sheet.document.sheet!.labels[2][0].content == "Independent" else { throw RenderError.failed("Copy to empty overwrote an existing label") }
        print("PASS: immediate text input, text-session undo, one-step centering, eight anchored resize handles, image replacement/crop/color/undo, ratio-locked side resize, continuous label navigation and copy-to-empty")
    }
}
