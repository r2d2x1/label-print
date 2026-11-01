import SwiftUI
import AppKit
import LabelCore

struct ObjectToolbar: View {
    @ObservedObject var store: EditorStore
    var body: some View {
        HStack(spacing: 8) {
            if let item = store.selected {
                if item.kind == .text {
                    FontChooser(item: item) { family in store.edit { $0.fontName = family } }.frame(width: 165)
                    TextField("Font size", value: Binding(get: { store.selected?.fontSize ?? 10 }, set: { value in store.edit { $0.fontSize = value } }),
                              format: .number.precision(.fractionLength(0...2))).frame(width: 50)
                        .disabled(item.automaticallyFitsText)
                    Text("pt").font(.caption).foregroundStyle(.secondary)
                    Stepper("Font size", value: Binding(get: { store.selected?.fontSize ?? 10 }, set: { value in store.edit { $0.fontSize = value } }), in: 1...200)
                        .labelsHidden().fixedSize().disabled(item.automaticallyFitsText)
                    Toggle("Auto Fit", isOn: Binding(get: { store.selected?.automaticallyFitsText ?? false }, set: { value in store.edit { $0.autoFitText = value } }))
                        .toggleStyle(.checkbox).fixedSize()
                    Toggle(isOn: Binding(get: { store.selected?.bold ?? false }, set: { value in store.edit { $0.bold = value } })) { Image(systemName: "bold") }.toggleStyle(.button).accessibilityLabel("Bold")
                    Toggle(isOn: Binding(get: { store.selected?.italic ?? false }, set: { value in store.edit { $0.italic = value } })) { Image(systemName: "italic") }.toggleStyle(.button).accessibilityLabel("Italic")
                    Menu {
                        ForEach(["left", "center", "right"], id: \.self) { alignment in
                            Button(alignment.capitalized) { store.edit { $0.alignment = alignment } }
                        }
                    } label: { Image(systemName: "text.align\(item.alignment)") }.fixedSize().help("Text alignment")
                } else if item.kind == .image {
                    Button("Replace Image…", action: { store.replaceSelectedImage() })
                    Button("Crop…") { store.endGesture(); store.cropImageItem = store.selected }
                    Toggle(isOn: Binding(get: { store.selected?.keepsAspectRatio ?? false }, set: { value in store.edit { $0.lockAspectRatio = value } })) {
                        Label("Keep Ratio", systemImage: item.keepsAspectRatio ? "lock.fill" : "lock.open")
                    }.toggleStyle(.button)
                } else if item.kind == .icon {
                    Button("Change Icon…") { store.iconPicker = true }
                } else { Label("QR Code", systemImage: "qrcode").foregroundStyle(.secondary) }
            } else {
                Text(store.selectedItems.count > 1 ? "\(store.selectedItems.count) objects selected" : "Click an object to select · Double-click text to type")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            if !store.selectionIDs.isEmpty {
                Button(action: store.centerSelectionOnLabel) { Image(systemName: "scope") }.help("Center on Label").accessibilityLabel("Center on Label")
                Menu {
                    ForEach(ItemAlignment.allCases, id: \.self) { alignment in
                        Button(alignment.title) { store.alignSelection(alignment) }
                    }
                    Divider()
                    Button("Fit to Printable Area", action: store.fitSelectionToLabel)
                    Button("Duplicate Object", action: store.duplicate)
                } label: { Image(systemName: "align.horizontal.center") }.fixedSize().help("Arrange objects")
                Button(role: .destructive, action: store.delete) { Image(systemName: "trash") }.help("Delete Object").accessibilityLabel("Delete Object")
            }
        }.font(.system(size: 12)).textFieldStyle(.roundedBorder)
            .padding(.horizontal, 12).frame(height: 40)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ObjectInspector: View {
    @ObservedObject var store: EditorStore
    @State private var layersExpanded = true
    private func number(_ title: String, _ key: WritableKeyPath<LabelItem, Double>) -> some View {
        HStack {
            Text(title).frame(width: 48, alignment: .leading)
            TextField(title, value: Binding(get: {
                guard let item = store.selected else { return 0 }
                return key == \LabelItem.width ? store.document.itemWidthMM(item) : item[keyPath: key]
            }, set: { store.setDimension(key, value: $0) }), format: .number.precision(.fractionLength(0...2)))
            Text("mm").foregroundStyle(.secondary)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(store.isA4 ? "LABEL \((store.document.sheet?.activeIndex ?? 0) + 1)" : "LABEL CONTENT")
                    .font(.caption).foregroundStyle(.secondary)
                if let item = store.selected {
                    Label(item.kind == .text ? "Text" : item.kind == .qr ? "QR Code" : item.kind == .image ? "Image" : "Icon",
                          systemImage: item.kind == .text ? "textformat" : item.kind == .image ? "photo" : item.kind == .qr ? "qrcode" : "star").font(.headline)
                    if item.kind == .text || item.kind == .qr {
                        TextEditor(text: Binding(get: { store.selected?.content ?? "" }, set: { value in store.editText(id: item.id, content: value) }))
                            .font(.body).frame(height: 75).padding(4)
                            .background(.background).overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                            .accessibilityLabel(item.kind == .text ? "Text content" : "QR content")
                    } else if item.kind == .image {
                        Text(item.content).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else { Text(item.content).font(.caption).foregroundStyle(.secondary) }
                    Divider()
                    HStack {
                        Text("Size").font(.headline)
                        Spacer()
                        if item.kind == .image {
                            Toggle(isOn: Binding(get: { store.selected?.keepsAspectRatio ?? false }, set: { value in store.edit { $0.lockAspectRatio = value } })) {
                                Image(systemName: item.keepsAspectRatio ? "lock.fill" : "lock.open")
                            }.toggleStyle(.button).help("Lock aspect ratio").accessibilityLabel("Lock aspect ratio")
                        }
                    }
                    number("Width", \.width).disabled(store.document.autoLength && item.kind == .text)
                    number("Height", \.height)
                    Divider()
                    Text("Position").font(.headline)
                    number("X", \.x); number("Y", \.y)
                    if item.kind == .image {
                        DisclosureGroup("More Image Tools") {
                            Button("Auto Crop Blank Edges", action: store.cropSelectedImage).padding(.top, 6)
                        }
                    }
                } else {
                    Text(store.selectedItems.count > 1 ? "Use the toolbar to arrange the selected objects." : "Click text or an image to edit it. A label containing one object selects it automatically.")
                        .foregroundStyle(.secondary).font(.callout)
                    if store.document.items.isEmpty {
                        Button("Add Text") { store.add(.text) }
                        Button("Add Image…") { store.importImage() }
                    }
                }
                if !store.document.items.isEmpty {
                    Divider()
                    DisclosureGroup("Layers (\(store.document.items.count))", isExpanded: $layersExpanded) {
                        VStack(spacing: 3) {
                            ForEach(store.document.items.reversed()) { item in
                                Button {
                                    store.endGesture(); store.select(item.id)
                                } label: {
                                    HStack {
                                        Image(systemName: item.kind == .text ? "textformat" : item.kind == .image ? "photo" : item.kind == .qr ? "qrcode" : "star").frame(width: 18)
                                        Text(item.content.isEmpty ? item.kind.rawValue.capitalized : item.content).lineLimit(1)
                                        Spacer()
                                    }.font(.callout).padding(7)
                                        .background(store.selectionIDs.contains(item.id) ? Color.accentColor.opacity(0.13) : .clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                }.buttonStyle(.plain).accessibilityLabel("Select layer: \(item.content)")
                            }
                        }.padding(.top, 6)
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.textFieldStyle(.roundedBorder)
    }
}

struct PrintSettingsPanel: View {
    @ObservedObject var store: EditorStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Print Settings").font(.title3.bold())
                Text(store.printerName).foregroundStyle(.secondary)
                Stepper(store.isA4 ? "Sheets: \(store.copies)" : "Copies: \(store.copies)", value: $store.copies, in: 1...99)
                if store.isA4 { SheetInspector(store: store) }
                else {
                    Toggle("Auto Cut", isOn: $store.cut).toggleStyle(.checkbox)
                    Toggle("Exact Printer Bitmap", isOn: $store.printDots).toggleStyle(.checkbox)
                    HStack {
                        Text("End Margin")
                        TextField("End margin", value: Binding(get: { store.document.marginMM }, set: { value in
                            guard value.isFinite else { return }; store.change { $0.marginMM = min(20, max(0, value)) }
                        }), format: .number.precision(.fractionLength(0...1))).frame(width: 65)
                        Text("mm")
                    }
                    Text("Automatic length includes the artwork and end margin. Finished labels are at least 25.4 mm long.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.textFieldStyle(.roundedBorder)
        }.frame(maxHeight: store.isA4 ? 590 : 220)
    }
}
