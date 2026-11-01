import SwiftUI
import AppKit
import LabelCore

struct PositionGrid: View {
    let template: SheetTemplate
    @Binding var selected: Set<Int>
    var source: Int? = nil
    @State private var anchor: Int?
    @State private var dragBase: Set<Int>?

    var body: some View {
        GeometryReader { geometry in
            let gap = 4.0
            let cellWidth = (geometry.size.width - Double(template.columns - 1) * gap) / Double(template.columns)
            let cellHeight = 25.0
            ZStack(alignment: .topLeading) {
                ForEach(0..<template.count, id: \.self) { index in
                    Button {
                        if NSEvent.modifierFlags.contains(.shift), let anchor {
                            selected.formUnion(Set(min(anchor, index)...max(anchor, index)))
                        } else if selected.contains(index) { selected.remove(index) }
                        else { selected.insert(index) }
                        if let source { selected.remove(source) }
                        anchor = index
                    } label: {
                        HStack(spacing: 2) {
                            Text("\(index + 1)")
                            if source == index { Image(systemName: "arrow.up.doc").font(.system(size: 9)) }
                        }
                        .font(.system(size: 11, weight: source == index ? .bold : .regular))
                        .frame(width: cellWidth, height: cellHeight)
                        .background(source == index ? Color.accentColor.opacity(0.3) : selected.contains(index) ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected.contains(index) || source == index ? Color.accentColor : Color.gray.opacity(0.25)))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain).disabled(source == index)
                    .accessibilityValue(source == index ? "Source" : selected.contains(index) ? "Selected" : "Not selected")
                    .help(source == index ? "Source label" : "Position \(index + 1) · Shift-click for a range")
                    .offset(x: Double(index % template.columns) * (cellWidth + gap),
                            y: Double(index / template.columns) * (cellHeight + gap))
                }
            }
            .frame(width: geometry.size.width, height: Double(template.rows) * 29 - 4, alignment: .topLeading)
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { value in
                if dragBase == nil { dragBase = selected }
                func cell(_ point: CGPoint) -> (Int, Int) {
                    (min(template.columns - 1, max(0, Int(point.x / (cellWidth + gap)))),
                     min(template.rows - 1, max(0, Int(point.y / (cellHeight + gap)))))
                }
                let start = cell(value.startLocation), end = cell(value.location)
                var rectangle: Set<Int> = []
                for row in min(start.1, end.1)...max(start.1, end.1) {
                    for column in min(start.0, end.0)...max(start.0, end.0) {
                        rectangle.insert(row * template.columns + column)
                    }
                }
                selected = (dragBase ?? []).union(rectangle)
                if let source { selected.remove(source) }
            }.onEnded { _ in dragBase = nil })
        }.frame(height: Double(template.rows) * 29 - 4)
    }
}

struct SheetInspector: View {
    @ObservedObject var store: EditorStore
    var body: some View {
        if let sheet = store.document.sheet {
            VStack(alignment: .leading, spacing: 12) {
                Text("A4 · 210 × 297 mm").font(.headline)
                Text("Print Positions").font(.headline)
                PositionGrid(template: sheet.template, selected: Binding(
                    get: { store.document.sheet?.printPositions ?? [] },
                    set: { value in store.editSheet { $0.printPositions = value } }))
                HStack {
                    Text("\(sheet.printPositions.count) / \(sheet.template.count) to print").font(.caption)
                    Spacer()
                    Button("All") { store.editSheet { $0.printPositions = Set(0..<$0.template.count) } }
                    Button("None") { store.editSheet { $0.printPositions = [] } }
                }
                Divider()
                Picker("Paper stock", selection: Binding(
                    get: { store.document.sheet?.plainPaper ?? true },
                    set: { value in store.editSheet { $0.plainPaper = value } })) {
                    Text("Plain A4").tag(true); Text("Label Sheets").tag(false)
                }.pickerStyle(.segmented).labelsHidden()
                Toggle("Print cut lines", isOn: Binding(
                    get: { store.document.sheet?.cutLines ?? false },
                    set: { value in store.editSheet { $0.cutLines = value } }))
                    .toggleStyle(.checkbox).disabled(!sheet.plainPaper || sheet.template.count == 1)
                Text("Light dashed lines for trimming square-corner labels.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Alignment Calibration") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("X offset")
                            TextField("X offset", value: Binding(get: { store.document.sheet?.offsetX ?? 0 }, set: { value in
                                guard value.isFinite else { return }; store.editSheet { $0.offsetX = max(-20, min(20, value)) }
                            }), format: .number.precision(.fractionLength(0...2)))
                            Text("mm")
                        }
                        HStack {
                            Text("Y offset")
                            TextField("Y offset", value: Binding(get: { store.document.sheet?.offsetY ?? 0 }, set: { value in
                                guard value.isFinite else { return }; store.editSheet { $0.offsetY = max(-20, min(20, value)) }
                            }), format: .number.precision(.fractionLength(0...2)))
                            Text("mm")
                        }
                    }.padding(.top, 8)
                }
            }
        }
    }
}

struct CopyLabelSheet: View {
    @ObservedObject var store: EditorStore
    @Environment(\.dismiss) private var dismiss
    @State private var targets: Set<Int> = []
    var body: some View {
        if let sheet = store.document.sheet {
            let source = sheet.activeIndex
            let overwritten = targets.filter { sheet.labels.indices.contains($0) && !sheet.labels[$0].isEmpty }.count
            VStack(alignment: .leading, spacing: 14) {
                Text("Copy Label \(source + 1) to…").font(.title2).bold()
                Text("Select destinations. Each copy can be edited independently.")
                    .foregroundStyle(.secondary)
                PositionGrid(template: sheet.template, selected: $targets, source: source)
                HStack {
                    Button("Row") {
                        targets = Set((source / sheet.template.columns * sheet.template.columns)..<((source / sheet.template.columns + 1) * sheet.template.columns)).subtracting([source])
                    }
                    Button("Column") { targets = Set((0..<sheet.template.count).filter { $0 % sheet.template.columns == source % sheet.template.columns && $0 != source }) }
                    Button("All") { targets = Set(0..<sheet.template.count).subtracting([source]) }
                    Button("Empty") { targets = Set(sheet.labels.indices.filter { $0 != source && sheet.labels[$0].isEmpty }) }
                    Button("Clear") { targets = [] }
                }
                Text("Source: \(source + 1) · \(targets.count) destinations")
                if overwritten > 0 {
                    Label("Contents of \(overwritten) non-empty labels will be replaced.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.callout)
                }
                Text("Shift-click selects a range; drag to select a rectangle. Printing positions stay unchanged. Undo restores this entire operation.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Apply Copy") { store.copyLabel(to: targets); dismiss() }
                        .buttonStyle(.borderedProminent).disabled(targets.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 420)
        }
    }
}
