import Foundation

/// Only square-corner, rectangular A4 layouts are supported.
public struct SheetTemplate: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let columns: Int
    public let rows: Int
    public let width: Double
    public let height: Double
    public let left: Double
    public let top: Double
    public var count: Int { columns * rows }
    public func rect(at index: Int) -> CGRect {
        CGRect(x: left + Double(index % columns) * width,
               y: top + Double(index / columns) * height, width: width, height: height)
    }
    public static let all: [SheetTemplate] = [
        .init(id: "blank", title: "Blank A4", columns: 1, rows: 1, width: 210, height: 297, left: 0, top: 0),
        .init(id: "3475", title: "Avery Zweckform · 3475", columns: 3, rows: 8, width: 70, height: 36, left: 0, top: 4.5),
        .init(id: "3474", title: "Avery Zweckform · 3474", columns: 3, rows: 8, width: 70, height: 37, left: 0, top: 0),
        .init(id: "3652", title: "Avery Zweckform · 3652", columns: 3, rows: 7, width: 70, height: 42.3, left: 0, top: 0)
    ]
    public static func find(_ id: String) -> SheetTemplate? { all.first { $0.id == id } }
}

public struct SheetLayout: Codable, Equatable, Sendable {
    public var templateID: String
    public var activeIndex = 0
    public var labels: [[LabelItem]]
    public var printPositions: Set<Int>
    public var plainPaper = true
    public var cutLines = true
    public var offsetX = 0.0
    public var offsetY = 0.0
    public var template: SheetTemplate { SheetTemplate.find(templateID) ?? SheetTemplate.all[0] }
    public init(templateID: String = "blank") {
        let template = SheetTemplate.find(templateID) ?? SheetTemplate.all[0]
        self.templateID = template.id
        labels = Array(repeating: [], count: template.count)
        printPositions = Set(0..<template.count)
    }
    /// Independent copies receive fresh object IDs. Source and print selection are unchanged.
    public mutating func copyLabel(from source: Int, to targets: Set<Int>) {
        guard labels.indices.contains(source) else { return }
        let original = labels[source]
        for index in targets where index != source && labels.indices.contains(index) {
            labels[index] = original.map { value in var copy = value; copy.id = UUID(); return copy }
        }
    }
    public func validated() throws {
        guard let template = SheetTemplate.find(templateID), labels.count == template.count,
              labels.indices.contains(activeIndex), printPositions.allSatisfy({ labels.indices.contains($0) }),
              offsetX.isFinite, offsetY.isFinite, abs(offsetX) <= 20, abs(offsetY) <= 20,
              labels.reduce(0, { $0 + $1.count }) <= 5000 else { throw DocumentError.invalid }
        for items in labels {
            var doc = LabelDocument(); doc.lengthMM = template.width; doc.tapeMM = template.height
            doc.autoLength = false; doc.items = items
            try doc.validateItems(width: template.width, height: template.height)
        }
    }
}
