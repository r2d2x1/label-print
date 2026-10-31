import SwiftUI
import AppKit
import LabelCore
import UniformTypeIdentifiers

struct LabelCanvas: View {
    @ObservedObject var store: EditorStore
    @FocusState private var focused: Bool
    @State private var editing: UUID?
    @State private var editingScale: Double?
    @State private var dragPreviews: [UUID: LabelItem] = [:]
    var body: some View {
        GeometryReader { geometry in
            let available = max(100, geometry.size.width - 120)
            let scale = editingScale ?? (store.fit ? min(available / store.document.effectiveLengthMM,
                                       max(1, (geometry.size.height - 180) / store.document.tapeMM)) : store.pointsPerMM)
            let labelWidth = store.document.effectiveLengthMM * scale
            let labelHeight = store.document.tapeMM * scale
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 22) {
                        HStack(alignment: .top, spacing: 10) {
                            verticalRuler(scale: scale, height: labelHeight).padding(.top, 61)
                            VStack(spacing: 10) {
                                horizontalRuler(scale: scale, width: labelWidth)
                                tape(scale: scale, width: labelWidth, height: labelHeight)
                            }
                        }
                    }
                    .padding(25)
                    .frame(minWidth: geometry.size.width, minHeight: max(100, geometry.size.height - 60))
                }
                HStack {
                    Text("⌘-click to multi-select · Drag to move · Double-click text to edit").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Print Preview", isOn: $store.printDots).toggleStyle(.checkbox)
                        .help("Show the exact 180 dpi black-and-white printer bitmap. This only changes the preview, not print quality.")
                    Picker("Zoom", selection: $store.fit) {
                        Text("Actual Size").tag(false); Text("Fit").tag(true)
                    }.pickerStyle(.segmented).frame(width: 175).labelsHidden()
                }.padding(14)
            }
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.55))
            .overlay(alignment: .topLeading) {
                if let error = store.renderError {
                    Text(error).font(.caption).foregroundStyle(.red).padding(12).background(.regularMaterial)
                }
            }
        }
        .focusable().focusEffectDisabled().focused($focused)
        .onDeleteCommand { if editing == nil { store.delete() } }
        .onChange(of: store.selection) { _, selection in
            if editing != selection { finishEditing() }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in store.importImage(url: url) } }
            }
            return true
        }
    }
    private func horizontalRuler(scale: Double, width: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                var path = Path(); path.move(to: CGPoint(x: 0, y: 26)); path.addLine(to: CGPoint(x: width, y: 26))
                for tick in RulerTick.ticks(length: store.document.effectiveLengthMM) {
                    let x = Double(tick.mm) * scale
                    let size = tick.isMajor ? 13.0 : tick.isMedium ? 9.0 : 4.0
                    if scale >= 3 || tick.isMedium {
                        path.move(to: CGPoint(x: x, y: 26 - size)); path.addLine(to: CGPoint(x: x, y: 30))
                    }
                }
                ctx.stroke(path, with: .color(.secondary), lineWidth: 0.7)
            }
            ForEach(RulerTick.ticks(length: store.document.effectiveLengthMM), id: \.mm) { tick in
                if tick.isMajor && (scale >= 3 || tick.mm % 50 == 0) {
                    Text("\(tick.mm)").position(x: Double(tick.mm) * scale, y: 5)
                    Text("\(tick.mm / 10)").position(x: Double(tick.mm) * scale, y: 42)
                }
            }
            Text("mm").position(x: width + 19, y: 5)
            Text("cm").position(x: width + 19, y: 42)
        }.font(.system(size: 10)).foregroundStyle(.secondary).frame(width: width, height: 51)
    }
    private func verticalRuler(scale: Double, height: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                var path = Path(); path.move(to: CGPoint(x: 29, y: 0)); path.addLine(to: CGPoint(x: 29, y: height))
                for tick in RulerTick.ticks(length: store.document.tapeMM) {
                    let y = Double(tick.mm) * scale
                    path.move(to: CGPoint(x: tick.isMedium ? 17 : 24, y: y)); path.addLine(to: CGPoint(x: 29, y: y))
                }
                ctx.stroke(path, with: .color(.secondary), lineWidth: 0.7)
            }
            ForEach(RulerTick.ticks(length: store.document.tapeMM), id: \.mm) { tick in
                if tick.isMedium || tick.mm == Int(store.document.tapeMM) {
                    Text("\(tick.mm)").position(x: 8, y: Double(tick.mm) * scale)
                }
            }
            Text("mm").position(x: 19, y: height + 16)
        }.font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 30, height: height + 30)
    }
    private func tape(scale: Double, width: Double, height: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white)
                .onTapGesture { finishEditing(); store.selection = nil; focused = true }
            if !store.printDots || !dragPreviews.isEmpty {
                ForEach(store.document.items) { original in
                    if let sprite = store.sprites[original.id] {
                        let displayed = dragPreviews[original.id] ?? original
                        let itemWidth = store.document.autoLength && original.kind == .text ? sprite.widthMM : displayed.width
                        Image(decorative: store.printDots ? sprite.image : sprite.smoothImage, scale: 1).resizable()
                            .interpolation(store.printDots ? .none : .high)
                            .frame(width: itemWidth * scale, height: displayed.height * scale)
                            .offset(x: displayed.x * scale, y: displayed.y * scale)
                            .allowsHitTesting(false)
                    }
                }
            } else if let image = store.preview {
                Image(decorative: image, scale: 1).resizable().interpolation(.none)
                    .frame(width: width, height: height).allowsHitTesting(false)
            }
            let inset = store.document.printableInsetMM * scale
            let bottom = store.document.printableBottomMM * scale
            Rectangle().fill(Color.gray.opacity(0.22)).frame(width: width, height: inset)
                .allowsHitTesting(false).help("Outside the printable area")
            Rectangle().fill(Color.gray.opacity(0.22)).frame(width: width, height: max(0, height - bottom))
                .offset(y: bottom).allowsHitTesting(false)
            Path { p in
                p.move(to: CGPoint(x: 0, y: inset)); p.addLine(to: CGPoint(x: width, y: inset))
                p.move(to: CGPoint(x: 0, y: bottom)); p.addLine(to: CGPoint(x: width, y: bottom))
            }.stroke(.gray.opacity(0.45), style: StrokeStyle(lineWidth: 0.7, dash: [4, 4])).allowsHitTesting(false)
            ForEach(store.document.items) { item in
                itemOverlay(item, scale: scale)
            }
            Path { path in
                if let x = store.snapX {
                    path.move(to: CGPoint(x: x * scale, y: 0)); path.addLine(to: CGPoint(x: x * scale, y: height))
                }
                if let y = store.snapY {
                    path.move(to: CGPoint(x: 0, y: y * scale)); path.addLine(to: CGPoint(x: width, y: y * scale))
                }
            }.stroke(Color.pink, style: StrokeStyle(lineWidth: 1, dash: [5, 3])).allowsHitTesting(false)

        }
        .frame(width: width, height: height)
        .coordinateSpace(name: "label-canvas")
        .background(.white)
        .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
    }
    private func finishDrag() {
        store.endGesture()
        dragPreviews = [:]
    }
    private func handleClick(_ item: LabelItem, scale: Double, edit: Bool) {
        finishEditing()
        let extending = NSEvent.modifierFlags.contains(.command)
        store.select(item.id, extending: extending)
        if edit && !extending && item.kind == .text { editing = item.id; editingScale = scale }
        else { focused = true }
    }
    private func finishEditing() { editing = nil; editingScale = nil }
    @ViewBuilder private func itemOverlay(_ item: LabelItem, scale: Double) -> some View {
        let selected = store.selectionIDs.contains(item.id)
        let displayed = dragPreviews[item.id] ?? item
        let width = (store.document.autoLength && item.kind == .text ? store.itemWidthMM(item) : displayed.width) * scale
        Group {
            if editing == item.id {
                InlineTextEditor(item: item, scale: scale, autoWidth: store.document.autoLength,
                                 onChange: { store.editText(id: item.id, content: $0) },
                                 onFinish: { if editing == item.id { finishEditing() } })
                    .overlay(Rectangle().stroke(Color.blue, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).allowsHitTesting(false))
            } else {
                Rectangle().fill(Color.white.opacity(0.001))
                    .overlay(Rectangle().stroke(selected ? Color.blue : .clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.kind == .text ? "Edit label text: \(item.content)" : "Select \(item.kind.rawValue): \(item.content)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                    .accessibilityAction { handleClick(item, scale: scale, edit: true) }
                    .accessibilityAction(named: Text("Toggle Selection")) { store.select(item.id, extending: true) }
                    .onTapGesture(count: 2) { handleClick(item, scale: scale, edit: true) }
                    .onTapGesture { handleClick(item, scale: scale, edit: false) }
                    .highPriorityGesture(TapGesture().modifiers(.command).onEnded {
                        finishEditing()
                        store.select(item.id, extending: true)
                        focused = true
                    })
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("label-canvas")).onChanged { value in
                        if !store.selectionIDs.contains(item.id) { store.select(item.id) }
                        store.drag(id: item.id, dx: value.translation.width / scale, dy: value.translation.height / scale, snapToleranceMM: min(0.8, 5 / scale))
                        dragPreviews = store.draggedItems
                    }.onEnded { _ in finishDrag() })
                    .overlay(alignment: .bottomTrailing) {
                        if selected && store.selectionIDs.count == 1 {
                            Rectangle().fill(.white).frame(width: 8, height: 8).overlay(Rectangle().stroke(Color.accentColor))
                                .offset(x: 4, y: 4)
                                .gesture(DragGesture(coordinateSpace: .named("label-canvas")).onChanged { value in
                                    store.drag(id: item.id, dx: value.translation.width / scale, dy: value.translation.height / scale, resize: true)
                                    dragPreviews = store.draggedItems
                                }.onEnded { _ in finishDrag() })
                        }
                    }
            }
        }
        .frame(width: max(width, editing == item.id ? 16 : 1), height: displayed.height * scale)
        .offset(x: displayed.x * scale, y: displayed.y * scale)
    }
}
