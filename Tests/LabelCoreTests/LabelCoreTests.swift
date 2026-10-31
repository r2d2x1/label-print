import Foundation
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
        try checks.testPhysicalDimensionsAndRulers()
        checks.testAutoLengthTracksArtworkAndMargin()
        try checks.testEmbeddedImageRoundTrip()
        checks.testMalformedGeometryAndVersionRejected()
        checks.testUndoRedoAndBranching()
        try checks.testMinimumLabelLengthAndCenteredMigration()
        print("PASS: 5 document checks (dimensions/rulers, auto length, file round-trip, invalid files, history)")
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
