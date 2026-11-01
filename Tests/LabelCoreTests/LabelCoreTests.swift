import Foundation
import AppKit
import LabelCore

func checkEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected \(a) == \(b)") }
func checkTrue(_ condition: Bool) { precondition(condition) }
func checkFalse(_ condition: Bool) { precondition(!condition) }
func checkThrows<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression(); fatalError("Expected error") } catch {}
}

@main struct LabelCoreChecks {
    static func main() throws {
        let checks = LabelCoreChecks()
        try checks.testAutoFitText()
        try checks.testImageAspectRatio()
        try checks.testSheetLayouts()
        try checks.testPhysicalDimensionsAndRulers()
        checks.testAutoLengthTracksArtworkAndMargin()
        try checks.testEmbeddedImageRoundTrip()
        checks.testMalformedGeometryAndVersionRejected()
        checks.testUndoRedoAndBranching()
        try checks.testMinimumLabelLengthAndCenteredMigration()
        print("PASS: 5 document checks (dimensions/rulers, auto length, file round-trip, invalid files, history)")
    }
    func testSheetLayouts() throws {
        for template in SheetTemplate.all {
            var layout = SheetLayout(templateID: template.id)
            try layout.validated()
            for index in 0..<template.count {
                let rect = template.rect(at: index)
                checkTrue(rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= 210.001 && rect.maxY <= 297.001)
            }
            layout.labels[0] = [LabelItem(kind: .text, content: "SOURCE", x: 2, y: 2, width: 20, height: 4)]
            layout.copyLabel(from: 0, to: Set(0..<template.count))
            checkEqual(layout.labels[0][0].content, "SOURCE")
            checkEqual(Set(layout.labels.flatMap { $0.map(\.id) }).count, template.count)
            try layout.validated()
            layout.printPositions.insert(-1)
            checkThrows(try layout.validated())
        }
        print("PASS: A4 template bounds, independent copies, unique IDs and position validation")
    }
    func testImageAspectRatio() throws {
        var item = LabelItem(kind: .image, content: "image", x: 0, y: 0, width: 8, height: 4)
        checkFalse(item.keepsAspectRatio)
        item.lockAspectRatio = true
        item.resizeImage(width: 12, maxWidth: 40, maxHeight: 12)
        checkEqual(item.width, 12); checkEqual(item.height, 6)
        item.resizeImage(height: 8, maxWidth: 40, maxHeight: 12)
        checkEqual(item.width, 16); checkEqual(item.height, 8)
        item.resizeImage(width: 100, maxWidth: 40, maxHeight: 12)
        checkEqual(item.width, 24); checkEqual(item.height, 12)
        let restored = try JSONDecoder().decode(LabelItem.self, from: JSONEncoder().encode(item))
        checkTrue(restored.keepsAspectRatio)
        item.lockAspectRatio = false
        item.resizeImage(width: 10, maxWidth: 40, maxHeight: 12)
        checkEqual(item.width, 24)
        print("PASS: image aspect ratio, width/height edits, size limits, persistence and unlock")
    }
    func testAutoFitText() throws {
        var item = LabelItem(kind: .text, content: "New text", x: 0, y: 0, width: 30, height: 8)
        let legacy = try JSONEncoder().encode(item)
        checkFalse(try JSONDecoder().decode(LabelItem.self, from: legacy).automaticallyFitsText)
        item.fitTextToBox(); checkEqual(item.fontSize, 10)
        item.autoFitText = true; item.fitTextToBox()
        let initial = item.fontSize
        item.width /= 2; item.height /= 2; item.fitTextToBox()
        checkTrue(item.fontSize < initial)
        let font = item.resolvedFont(ofSize: item.fontSize)
        checkTrue(font.ascender - font.descender + font.leading <= item.height * 72 / 25.4)
        let restored = try JSONDecoder().decode(LabelItem.self, from: JSONEncoder().encode(item))
        checkTrue(restored.automaticallyFitsText)
        item.autoFitText = false; let fixed = item.fontSize
        item.height *= 2; item.fitTextToBox(); checkEqual(item.fontSize, fixed)
        print("PASS: text auto fit, fixed size, font bounds and persistence")
    }
    func testMinimumLabelLengthAndCenteredMigration() throws {
        var short = LabelDocument.blank; short.lengthMM = 20
        short.items = [LabelItem(kind: .image, content: "centered", x: 5, y: 2, width: 10, height: 8)]
        let migrated = try short.normalizingMinimumLength().validated()
        checkEqual(migrated.lengthMM, 25.4)
        checkTrue(abs(migrated.items[0].x + 5 - migrated.lengthMM / 2) < 0.00001)
        checkEqual(migrated.items[0].width, 10)
        checkEqual(migrated.items[0].y, 2)
        checkEqual(migrated.pixelWidth, 180)
        checkEqual(migrated.normalizingMinimumLength(), migrated)
        var auto = LabelDocument(); auto.items = []
        checkEqual(auto.effectiveLengthMM, 25.4)
        checkEqual(LabelDocument.blank.normalizingMinimumLength(), LabelDocument.blank)
        print("PASS: minimum 25.4 mm, legacy short-label symmetric padding, no artwork scaling, idempotence, unchanged 40 mm")
    }
    func testPhysicalDimensionsAndRulers() throws {
        var fixture = LabelDocument.sample; fixture.autoLength = false
        let doc = try fixture.validated()
        checkEqual(doc.pixelWidth, 425)
        checkEqual(doc.pixelHeight, 85)
        checkEqual(RulerTick.ticks(length: 60).count, 61)
        checkTrue(RulerTick.ticks(length: 60)[10].isMajor)
        checkFalse(RulerTick.ticks(length: 60)[9].isMedium)
        checkEqual(LabelDocument.printableDots(24), 128)
    }
    func testAutoLengthTracksArtworkAndMargin() {
        var doc = LabelDocument.sample
        checkTrue(doc.autoLength)
        checkTrue(doc.effectiveLengthMM < 59) // Old 40 mm boxes no longer waste tape.
        let original = doc.effectiveLengthMM
        doc.items[1].width = 200
        checkEqual(doc.effectiveLengthMM, original) // Fit uses text, not empty box space.
        doc.items[1].content = "A much longer storage box heading"
        checkTrue(doc.effectiveLengthMM > original)
        doc.items[1].content = "A"; doc.items[2].content = "B"
        checkTrue(doc.effectiveLengthMM < original)
        let short = doc.effectiveLengthMM
        doc.items[1].x += 10
        checkTrue(doc.effectiveLengthMM > short)
        let beforeMargin = doc.effectiveLengthMM; doc.marginMM += 2
        checkEqual(doc.effectiveLengthMM, beforeMargin + 2)
        doc.autoLength = false; doc.lengthMM = 70
        checkEqual(doc.effectiveLengthMM, 70)
    }
    func testEmbeddedImageRoundTrip() throws {
        var doc = LabelDocument.sample
        var item = LabelItem(kind: .image, content: "sample.png", x: 1, y: 1, width: 5, height: 5)
        item.imageData = Data([1, 2, 3]); doc.items.append(item)
        let data = try JSONEncoder().encode(doc)
        checkEqual(try JSONDecoder().decode(LabelDocument.self, from: data).validated(), doc)
    }
    func testMalformedGeometryAndVersionRejected() {
        var doc = LabelDocument.sample; doc.items[0].width = -.infinity
        checkThrows(try doc.validated())
        doc = .sample; doc.version = 100
        checkThrows(try doc.validated())
        doc = .sample; doc.items[0].height = 100
        checkThrows(try doc.validated())
    }
    func testUndoRedoAndBranching() {
        var history = DocumentHistory(); let original = LabelDocument.sample
        var changed = original; changed.name = "Changed"; history.record(original)
        checkEqual(history.undo(changed), original)
        checkEqual(history.redo(original), changed)
        _ = history.undo(changed); history.record(original)
        checkFalse(history.canRedo)
    }
}
