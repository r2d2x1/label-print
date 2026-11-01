import SwiftUI
import AppKit
import LabelCore
import UniformTypeIdentifiers

struct LabelCanvas: View {
    @ObservedObject var store: EditorStore
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Bool
    @State private var editing: UUID?
    @State private var editingScale: Double?
    @State private var pan = CGSize.zero
    @State private var dragPreviews: [UUID: LabelItem] = [:]
    var body: some View {
        GeometryReader { geometry in
            let overview = store.isA4 && store.sheetOverview
            let widthMM = overview ? 210 : store.document.effectiveLengthMM
            let heightMM = overview ? 297 : store.document.tapeMM
            let available = max(100, geometry.size.width - 120)
            let scale = editingScale ?? (store.fit ? min(available / widthMM,
                                       max(0.2, (geometry.size.height - 160) / heightMM)) : store.pointsPerMM)
            let labelWidth = widthMM * scale
            let labelHeight = heightMM * scale
            VStack(spacing: 0) {
                ObjectToolbar(store: store)
                Divider()
                GeometryReader { viewport in
                    let labelX = 52 + (viewport.size.width - 52 - labelWidth) / 2 + pan.width
                    let labelY = 44 + (viewport.size.height - 44 - labelHeight) / 2 + pan.height
                    ZStack(alignment: .topLeading) {
                        canvasColor
                        Group {
                            if overview {
                                sheetPage(scale: scale, width: labelWidth, height: labelHeight)
                            } else {
                                tape(scale: scale, width: labelWidth, height: labelHeight)
                            }
                        }.offset(x: labelX, y: labelY)
                        rulers(scale: scale, origin: CGPoint(x: labelX, y: labelY),
                               labelSize: CGSize(width: labelWidth, height: labelHeight))
                            .allowsHitTesting(false)
                    }
                    .clipped()
                    .background(CanvasScrollZoom { delta, point in
                        changeZoom(from: scale, factor: exp(delta * 0.015), at: point,
                                   viewport: viewport.size, widthMM: widthMM, heightMM: heightMM)
                    })
                }
                HStack(spacing: 10) {
                    Text(store.message).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).help(store.message).frame(maxWidth: .infinity, alignment: .leading)
                    if store.busy { ProgressView().controlSize(.small) }
                    Button { changeZoom(from: scale, factor: 1 / 1.2) } label: {
                        Image(systemName: "minus").frame(width: 32, height: 28)
                    }.help("Zoom out")
                    Text("\(Int((scale / (72 / 25.4) * 100).rounded()))%")
                        .monospacedDigit().frame(minWidth: 44)
                    Button { changeZoom(from: scale, factor: 1.2) } label: {
                        Image(systemName: "plus").frame(width: 32, height: 28)
                    }.help("Zoom in")
                    Button {
                        finishEditing(); pan = .zero; store.fit = false; store.pointsPerMM = 72 / 25.4
                    } label: {
                        Text("Actual Size").frame(width: 74, height: 28)
                    }
                    Button { finishEditing(); pan = .zero; store.fit = true } label: {
                        Text(overview ? "Fit Page" : "Fit View").frame(width: 64, height: 28)
                    }
                }
                .font(.system(size: 12))
                .buttonStyle(CanvasToolbarButtonStyle())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .top) { Divider() }
            }
            .background(canvasColor)
            .onChange(of: store.textEditRequest) { _, request in
                if let request { editing = request; editingScale = scale }
                else { editing = nil; editingScale = nil }
            }
            .onAppear { if let request = store.textEditRequest { editing = request; editingScale = scale } }
            .onChange(of: store.sheetOverview) { _, _ in pan = .zero }
            .onChange(of: store.fit) { _, fit in if fit { pan = .zero } }
            .overlay(alignment: .topLeading) {
                if let error = store.renderError {
                    Text(error).font(.caption).foregroundStyle(.red).padding(12).background(.regularMaterial)
                }
            }
        }
        .focusable().focusEffectDisabled().focused($focused)
        .onDeleteCommand { if editing == nil { store.delete() } }
        .onChange(of: store.selection) { _, selection in
            if editing != selection && store.textEditRequest != selection { finishEditing() }
        }
        .onKeyPress(.return) {
            if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable { return .ignored }
            guard editing == nil, let item = store.selected, item.kind == .text else { return .ignored }
            store.beginTextEditing(item.id); return .handled
        }
        .onKeyPress(.tab) {
            if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable { return .ignored }
            guard editing == nil, !store.document.items.isEmpty else { return .ignored }
            let current = store.document.items.firstIndex { $0.id == store.selection } ?? -1
            store.select(store.document.items[(current + 1) % store.document.items.count].id)
            return .handled
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in store.importImage(url: url) } }
            }
            return true
        }
    }
    private var canvasColor: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.18, blue: 0.21)
            : Color(red: 0.91, green: 0.93, blue: 0.95)
    }

    private func changeZoom(from scale: Double, factor: Double, at point: CGPoint? = nil,
                            viewport: CGSize? = nil, widthMM: Double = 0, heightMM: Double = 0) {
        guard factor.isFinite else { return }
        let next = min(100, max(0.5, scale * factor))
        if let point, let viewport {
            let oldX = 52 + (viewport.width - 52 - widthMM * scale) / 2 + pan.width
            let oldY = 44 + (viewport.height - 44 - heightMM * scale) / 2 + pan.height
            let ratio = next / scale
            pan = CGSize(width: point.x - (point.x - oldX) * ratio - (52 + (viewport.width - 52 - widthMM * next) / 2),
                         height: point.y - (point.y - oldY) * ratio - (44 + (viewport.height - 44 - heightMM * next) / 2))
        }
        finishEditing(); store.pointsPerMM = next; store.fit = false
    }

    private func rulers(scale: Double, origin: CGPoint, labelSize: CGSize) -> some View {
        Canvas { context, size in
            let left = 52.0, top = 44.0
            // The ruler strips share the canvas color and cover overflowing label content.
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: top)), with: .color(canvasColor))
            context.fill(Path(CGRect(x: 0, y: 0, width: left, height: size.height)), with: .color(canvasColor))
            for horizontal in [true, false] {
                let start = horizontal ? left : top
                let extent = horizontal ? size.width : size.height
                let zero = horizontal ? origin.x : origin.y
                let length = horizontal ? labelSize.width : labelSize.height
                let baseline = horizontal ? top : left
                func point(_ along: Double, _ across: Double) -> CGPoint {
                    horizontal ? CGPoint(x: along, y: across) : CGPoint(x: across, y: along)
                }
                var ticks = Path()
                ticks.move(to: point(start, baseline))
                ticks.addLine(to: point(extent, baseline))
                let first = Int(ceil((start - zero) / scale))
                let last = Int(floor((extent - zero) / scale))
                if first <= last {
                    for mm in first...last {
                        let position = zero + Double(mm) * scale
                        let major = mm % 10 == 0
                        let tickLength = major ? 17.0 : mm % 5 == 0 ? 11.0 : 6.0
                        ticks.move(to: point(position, baseline - tickLength))
                        ticks.addLine(to: point(position, baseline))
                        if major && (scale >= 2 || mm % 50 == 0) {
                            context.draw(Text("\(mm / 10)").font(.system(size: 10)).foregroundColor(.secondary),
                                         at: point(position, horizontal ? 12 : 16))
                        }
                    }
                }
                context.stroke(ticks, with: .color(.secondary), lineWidth: 0.7)
                let lower = max(start, zero), upper = min(extent, zero + length)
                if lower < upper {
                    var dimension = Path()
                    dimension.move(to: point(lower, baseline)); dimension.addLine(to: point(upper, baseline))
                    for endpoint in [zero, zero + length] where endpoint >= start && endpoint <= extent {
                        dimension.move(to: point(endpoint, baseline - 5))
                        dimension.addLine(to: point(endpoint, baseline + 5))
                    }
                    context.stroke(dimension, with: .color(.accentColor), lineWidth: 2)
                    let mm = length / scale
                    let value = (mm / 10).formatted(.number.precision(.fractionLength(0...2))) + " cm"
                    var badge = context
                    badge.translateBy(x: horizontal ? (lower + upper) / 2 : baseline,
                                      y: horizontal ? baseline : (lower + upper) / 2)
                    if !horizontal { badge.rotate(by: .degrees(-90)) }
                    let text = Text(value).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                    let resolved = badge.resolve(text)
                    let measured = resolved.measure(in: CGSize(width: 150, height: 24))
                    badge.fill(Path(roundedRect: CGRect(x: -measured.width / 2 - 8, y: -10,
                                                       width: measured.width + 16, height: 20), cornerRadius: 9),
                               with: .color(.accentColor))
                    badge.draw(resolved, at: .zero)
                }
            }
            // Project the label boundaries onto the rulers.
            var guides = Path()
            for x in [origin.x, origin.x + labelSize.width] where x >= left && x <= size.width {
                guides.move(to: CGPoint(x: x, y: top + 6))
                guides.addLine(to: CGPoint(x: x, y: max(top + 6, origin.y)))
            }
            for y in [origin.y, origin.y + labelSize.height] where y >= top && y <= size.height {
                guides.move(to: CGPoint(x: left + 6, y: y))
                guides.addLine(to: CGPoint(x: max(left + 6, origin.x), y: y))
            }
            context.stroke(guides, with: .color(.accentColor.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 0.7, dash: [4, 4]))
            context.draw(Text("cm").font(.system(size: 11)).foregroundColor(.secondary),
                         at: CGPoint(x: 22, y: 16))
        }
    }
    private func sheetPage(scale: Double, width: Double, height: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Color.white
            if let image = store.sheetPreview {
                Image(decorative: image, scale: 1).resizable().frame(width: width, height: height)
                    .allowsHitTesting(false)
            }
            if let sheet = store.document.sheet {
                ForEach(sheet.labels.indices, id: \.self) { index in
                    let rect = sheet.template.rect(at: index)
                    Rectangle().fill(Color.clear)
                        .overlay(Rectangle().stroke(index == sheet.activeIndex ? Color.accentColor : Color.gray.opacity(0.35),
                            style: StrokeStyle(lineWidth: index == sheet.activeIndex ? 1.5 : 0.5,
                                               dash: index == sheet.activeIndex ? [] : [3, 3])))
                        .overlay(alignment: .topLeading) {
                            Text("\(index + 1)").font(.system(size: 9)).foregroundStyle(.secondary).padding(3)
                        }
                        .contentShape(Rectangle())
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .overlay {
                            let editable = sheet.labels[index].first { $0.kind == .text || $0.kind == .image }
                            SheetCellInput(label: "Label \(index + 1)", editPoint: editable.map {
                                CGPoint(x: ($0.x + $0.width / 2) * scale, y: ($0.y + $0.height / 2) * scale)
                            }) { point, edit in
                                openCell(index, location: point, scale: scale, edit: edit)
                            }
                        }
                        .offset(x: rect.minX * scale, y: rect.minY * scale)
                }
            }
        }.frame(width: width, height: height)
            .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
    }
    private func openCell(_ index: Int, location: CGPoint, scale: Double, edit: Bool) {
        finishEditing()
        guard let sheet = store.document.sheet else { return }
        let point = CGPoint(x: location.x / scale, y: location.y / scale)
        let hit = sheet.labels[index].reversed().first { item in
            CGRect(x: item.x, y: item.y, width: item.width, height: item.height).contains(point)
        }
        store.focusLabel(index, objectID: hit?.id, editText: edit && hit != nil)
        // Keep focus stable while the text view is created after the page transition.
        if !edit { focused = true }
    }
    private func tape(scale: Double, width: Double, height: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.white)
                .onTapGesture {
                    finishEditing()
                    store.selection = store.document.items.count == 1 ? store.document.items.first?.id : nil
                    focused = true
                }
            if store.isA4 || !store.printDots || !dragPreviews.isEmpty {
                ForEach(store.document.items) { original in
                    if let sprite = store.sprites[original.id] {
                        let displayed = dragPreviews[original.id] ?? original
                        let itemWidth = store.document.autoLength && original.kind == .text ? sprite.widthMM : displayed.width
                        let resizingText = original.kind == .text && (displayed.width != original.width || displayed.height != original.height)
                        let resizedSprite = resizingText ? try? LabelRenderer.renderSprite(displayed, widthMM: itemWidth, smooth: store.isA4 || !store.printDots, color: store.isA4) : nil
                        Image(decorative: resizedSprite ?? (store.printDots && !store.isA4 ? sprite.image : sprite.smoothImage), scale: 1).resizable()
                            .interpolation(store.printDots && !store.isA4 ? .none : .high)
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
            if store.document.items.isEmpty && width > 180 && height > 55 {
                HStack(spacing: 12) {
                    Button { store.add(.text) } label: { Label("Add Text", systemImage: "textformat") }
                    Button { store.importImage() } label: { Label("Image", systemImage: "photo") }
                    Button { store.add(.qr) } label: { Label("QR", systemImage: "qrcode") }
                }.buttonStyle(.borderless).font(.callout)
                    .frame(width: width, height: height)
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
        if edit && !extending && item.kind == .text {
            store.beginTextEditing(item.id); editing = item.id; editingScale = scale
        } else if edit && !extending && item.kind == .image { store.cropImageItem = item }
        else { focused = true }
    }
    private func finishEditing() { store.finishTextEditing(); editing = nil; editingScale = nil }
    @ViewBuilder private func itemOverlay(_ item: LabelItem, scale: Double) -> some View {
        let selected = store.selectionIDs.contains(item.id)
        let displayed = dragPreviews[item.id] ?? item
        let width = (store.document.autoLength && item.kind == .text ? store.itemWidthMM(item) : displayed.width) * scale
        Group {
            if editing == item.id {
                InlineTextEditor(item: item, scale: scale, autoWidth: store.document.autoLength, selectAllOnStart: store.textEditSelectAll,
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
                    .accessibilityAction { handleClick(item, scale: scale, edit: item.kind == .text) }
                    .accessibilityAction(named: Text("Toggle Selection")) { store.select(item.id, extending: true) }
                    .simultaneousGesture(TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { value in
                        switch value {
                        case .first: handleClick(item, scale: scale, edit: true)
                        case .second: handleClick(item, scale: scale, edit: false)
                        }
                    })
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
                    .overlay {
                        if selected && store.selectionIDs.count == 1 {
                            GeometryReader { geometry in
                                ForEach(ResizeHandle.allCases, id: \.self) { handle in
                                    RoundedRectangle(cornerRadius: 1).fill(.white)
                                        .frame(width: 7, height: 7).overlay(Rectangle().stroke(Color.accentColor))
                                        .frame(width: 20, height: 20).contentShape(Rectangle())
                                        .position(x: (handle.horizontal + 1) * geometry.size.width / 2,
                                                  y: (handle.vertical + 1) * geometry.size.height / 2)
                                        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("label-canvas")).onChanged { value in
                                            store.drag(id: item.id, dx: value.translation.width / scale, dy: value.translation.height / scale,
                                                       resize: true, handle: handle)
                                            dragPreviews = store.draggedItems
                                        }.onEnded { _ in finishDrag() })
                                }
                            }.allowsHitTesting(true)
                        }
                    }
            }
        }
        .frame(width: max(width, editing == item.id ? 16 : 1), height: displayed.height * scale)
        .offset(x: displayed.x * scale, y: displayed.y * scale)
    }
}

/// A local event monitor keeps wheel zoom scoped to the canvas without intercepting clicks.
private struct CanvasScrollZoom: NSViewRepresentable {
    var zoom: (Double, CGPoint) -> Void
    func makeNSView(context: Context) -> ZoomView { ZoomView(zoom: zoom) }
    func updateNSView(_ view: ZoomView, context: Context) { view.zoom = zoom }
    static func dismantleNSView(_ view: ZoomView, coordinator: ()) { view.stopMonitoring() }

    final class ZoomView: NSView {
        var zoom: (Double, CGPoint) -> Void
        private var monitor: Any?
        init(zoom: @escaping (Double, CGPoint) -> Void) {
            self.zoom = zoom
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                let delta = event.scrollingDeltaY
                if delta != 0 { self.zoom(delta, self.convert(event.locationInWindow, from: nil)) }
                return nil
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
        deinit { stopMonitoring() }
    }
}

private struct CanvasToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
