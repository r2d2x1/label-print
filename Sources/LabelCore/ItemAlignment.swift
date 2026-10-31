import Foundation

public enum ItemAlignment: String, CaseIterable, Sendable {
    case left, horizontalCenter, right, top, verticalCenter, bottom
    public var title: String {
        switch self {
        case .left: return "Align Left"
        case .horizontalCenter: return "Center Horizontally"
        case .right: return "Align Right"
        case .top: return "Align Top"
        case .verticalCenter: return "Center Vertically"
        case .bottom: return "Align Bottom"
        }
    }
    public var symbol: String {
        switch self {
        case .left: return "align.horizontal.left"
        case .horizontalCenter: return "align.horizontal.center"
        case .right: return "align.horizontal.right"
        case .top: return "align.vertical.top"
        case .verticalCenter: return "align.vertical.center"
        case .bottom: return "align.vertical.bottom"
        }
    }
}

public extension LabelDocument {
    /// Align a single object to the tape, or multiple objects to their group bounds.
    /// Use visible text widths in automatic mode, matching preview geometry.
    mutating func align(_ ids: Set<UUID>, to alignment: ItemAlignment) {
        let selected = items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        let single = selected.count == 1
        let labelLength = effectiveLengthMM
        // Anchor horizontal single-item alignment to the current tape length.
        // Otherwise automatic fitting would move the target edge immediately.
        if single && autoLength && [.left, .horizontalCenter, .right].contains(alignment) {
            for index in items.indices where items[index].kind == .text {
                items[index].width = itemWidthMM(items[index])
            }
            lengthMM = labelLength; autoLength = false
        }
        let left = single ? 0 : selected.map(\.x).min()!
        let right = single ? labelLength : selected.map { $0.x + itemWidthMM($0) }.max()!
        let top = single ? printableInsetMM : selected.map(\.y).min()!
        let bottom = single ? printableBottomMM : selected.map { $0.y + $0.height }.max()!
        for index in items.indices where ids.contains(items[index].id) {
            let width = itemWidthMM(items[index])
            if autoLength && items[index].kind == .text { items[index].width = width }
            switch alignment {
            case .left: items[index].x = left
            case .horizontalCenter: items[index].x = (left + right - width) / 2
            case .right: items[index].x = right - width
            case .top: items[index].y = top
            case .verticalCenter: items[index].y = (top + bottom - items[index].height) / 2
            case .bottom: items[index].y = bottom - items[index].height
            }
            items[index].x = max(0, items[index].x)
            items[index].y = max(0, items[index].y)
        }
    }
}
