import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LabelCore

struct EditorView: View {
    @ObservedObject var store: EditorStore
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tools
            Divider()
            HStack(spacing: 0) {
                LabelCanvas(store: store).frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                inspector.frame(width: 280).background(Color(nsColor: .controlBackgroundColor))
            }
            Divider()
            settings.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            HStack(spacing: 18) {
                Text(store.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .textSelection(.enabled).help(store.message)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Stepper("Copies: \(store.copies)", value: $store.copies, in: 1...99).fixedSize()
                Toggle("Auto Cut", isOn: $store.cut).toggleStyle(.checkbox)
                    .help("Trim the initial blank leader and cut finished labels. The first label still consumes about 25 mm of extra tape.")
                Button { Task { await store.printLabel() } } label: { Label("Print", systemImage: "printer").frame(width: 90) }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy || store.preview == nil)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1180, minHeight: 720)
        .sheet(isPresented: $store.iconPicker) { IconPicker(store: store) }
        .task { await store.refreshPrinter() }
    }
    private func tool(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20, weight: .regular)).frame(height: 24)
                Text(title).font(.system(size: 11)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }.frame(minWidth: 52).frame(height: 48)
                .fixedSize(horizontal: true, vertical: false).padding(.horizontal, 3)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).symbolRenderingMode(.monochrome).help(title)
    }
    private var header: some View {
        HStack(spacing: 14) {
            tool("New", "doc.badge.plus", action: store.newLabel)
            tool("Open", "folder", action: store.open)
            tool("Save", "square.and.arrow.down", action: { store.save() })
            tool("Export", "square.and.arrow.up", action: store.export).disabled(store.preview == nil)
            Spacer(minLength: 12)
            VStack(spacing: 3) {
                TextField("Label name", text: Binding(get: { store.document.name }, set: { value in store.change { $0.name = value } }))
                    .font(.headline).textFieldStyle(.plain).multilineTextAlignment(.center).frame(width: 200)
                Text(store.dirty ? "Edited" : " ").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Circle().fill(store.connected ? Color.green : .gray).frame(width: 8, height: 8)
            Text("PT-2430PC").font(.callout)
            Button { Task { await store.refreshPrinter() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(.plain).disabled(store.busy)
            Picker("Tape", selection: Binding(get: { store.document.tapeMM }, set: store.resizeTape)) {
                ForEach([6.0, 9, 12, 18, 24], id: \.self) { Text("\(Int($0)) mm").tag($0) }
            }.frame(width: 120)
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }
    private var tools: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("INSERT").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    tool("Text", "textformat", action: { store.add(.text) })
                    tool("Image", "photo", action: { store.importImage() })
                    tool("Paste Image", "clipboard", action: { store.pasteImage() })
                    tool("Icon", "star", action: { store.iconPicker = true })
                    tool("QR", "qrcode", action: { store.add(.qr) })
                }
            }
            Divider().frame(height: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text("ALIGN OBJECTS").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(ItemAlignment.allCases, id: \.self) { alignment in
                        tool(alignmentLabel(alignment), alignment.symbol, action: { store.alignSelection(alignment) })
                            .disabled(store.selectionIDs.isEmpty)
                            .accessibilityLabel(alignment.title)
                            .help(alignment.title + (store.selectedItems.count == 1 ? " to label; horizontal alignment fixes current length" : " within selection"))
                    }
                    tool("Fit to Label", "arrow.up.left.and.arrow.down.right", action: store.fitSelectionToLabel)
                        .disabled(store.selectionIDs.isEmpty)
                        .help("Fit selected objects to the printable area without distortion; fixes current label length")

                }
            }
            Divider().frame(height: 54)
            HStack(spacing: 8) {
                tool("Undo", "arrow.uturn.backward", action: store.undo).disabled(!store.history.canUndo)
                tool("Redo", "arrow.uturn.forward", action: store.redo).disabled(!store.history.canRedo)
                tool("Delete", "trash", action: store.delete).disabled(store.selectionIDs.isEmpty)
                    .help("Delete selected objects")
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 20).padding(.vertical, 10)
    }
    private func alignmentLabel(_ alignment: ItemAlignment) -> String {
        switch alignment {
        case .left: return "Left"
        case .horizontalCenter: return "H Center"
        case .right: return "Right"
        case .top: return "Top"
        case .verticalCenter: return "V Center"
        case .bottom: return "Bottom"
        }
    }
    private func number(_ label: String, _ key: WritableKeyPath<LabelItem, Double>, suffix: String = "mm") -> some View {
        HStack {
            Text(label).frame(width: 50, alignment: .leading)
            TextField(label, value: Binding(get: {
                guard let item = store.selected else { return 0 }
                return key == \LabelItem.width ? store.document.itemWidthMM(item) : item[keyPath: key]
            }, set: { value in store.edit { $0[keyPath: key] = value } }),
                      format: .number.precision(.fractionLength(0...2)))
            Text(suffix).foregroundStyle(.secondary).frame(width: 24)
        }
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("OBJECT PROPERTIES").font(.caption).foregroundStyle(.secondary)
                Divider()
                if store.selectedItems.count > 1 {
                    Text("\(store.selectedItems.count) items selected").font(.headline)
                    Text("Align objects within the selected group's bounds.").foregroundStyle(.secondary)
                    Text("⌘-click an item to add or remove it. Drag a selected item to move the group.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Duplicate", action: store.duplicate)
                        Button("Delete", action: store.delete)
                    }
                } else if let item = store.selected {
                    Text(item.kind == .qr ? "QR Code" : item.kind.rawValue.capitalized + (item.kind == .text ? " Box" : "")).font(.headline)
                    if item.kind == .qr {
                        Text(item.kind == .qr ? "QR Content" : "Text").font(.subheadline)
                        TextEditor(text: Binding(get: { store.selected?.content ?? "" }, set: { value in store.edit { $0.content = value } }))
                            .font(.body).frame(height: 85).padding(5)
                            .background(.background).clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    }
                    if item.kind == .text {
                        FontChooser(item: item) { family in
                            store.edit { $0.fontName = family }
                        }
                        number("Size", \.fontSize, suffix: "pt")
                        HStack {
                            Toggle("Bold", isOn: Binding(get: { store.selected?.bold ?? false }, set: { value in store.edit { $0.bold = value } }))
                            Toggle("Italic", isOn: Binding(get: { store.selected?.italic ?? false }, set: { value in store.edit { $0.italic = value } }))
                        }.toggleStyle(.button)
                        Picker("Align", selection: Binding(get: { store.selected?.alignment ?? "left" }, set: { value in store.edit { $0.alignment = value } })) {
                            Image(systemName: "text.alignleft").tag("left")
                            Image(systemName: "text.aligncenter").tag("center")
                            Image(systemName: "text.alignright").tag("right")
                        }.pickerStyle(.segmented)
                    }
                    if item.kind == .icon {
                        Label(item.content, systemImage: item.content)
                        Button("Choose Icon…") { store.iconPicker = true }
                    }
                    if item.kind == .image {
                        Text(item.content).font(.caption).foregroundStyle(.secondary)
                        Button("Auto Crop Blank Edges") { store.cropSelectedImage() }
                            .help("Convert to grayscale and trim white or transparent edges. Keeps the image position and bounding box.")
                    }
                    Divider()
                    Text("Position · mm").font(.headline)
                    number("X", \.x); number("Y", \.y)
                    Divider()
                    Text("Size · mm").font(.headline)
                    number("Width", \.width).disabled(store.document.autoLength && item.kind == .text)
                    number("Height", \.height)
                    Divider()
                    HStack {
                        Button { store.duplicate() } label: { Label("Duplicate", systemImage: "square.on.square") }
                        Button(role: .destructive) { store.delete() } label: { Label("Delete", systemImage: "trash") }.help("Delete selected item")
                    }
                } else {
                    Text("Select an item on the label to edit its content and position.")
                        .foregroundStyle(.secondary)

                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.textFieldStyle(.roundedBorder)
    }
    private var settings: some View {
        HStack(spacing: 16) {
            Text("LABEL").font(.caption).foregroundStyle(.secondary).frame(width: 65, alignment: .leading)
            Text("Length")
            TextField("Length", value: Binding(get: { store.document.effectiveLengthMM }, set: store.setLength),
                      format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 65)
                .help("PT-2430PC minimum label length: 25.4 mm")
            Text("mm").foregroundStyle(.secondary)
            Toggle("Fit to Content", isOn: Binding(get: { store.document.autoLength }, set: store.setAutoLength))
                .toggleStyle(.checkbox)
            Divider().frame(height: 24).padding(.horizontal, 10)
            Text("Margins")
            TextField("Margins", value: Binding(get: { store.document.marginMM }, set: { value in
                guard value.isFinite else { return }
                store.change { $0.marginMM = min(20, max(0, value)) }
            }), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 65)
            Text("mm").foregroundStyle(.secondary)
            Spacer()
        }
    }

}

struct IconPicker: View {
    @ObservedObject var store: EditorStore
    @Environment(\.dismiss) var dismiss
    @State private var search = ""
    private let icons = ["shippingbox", "archivebox", "bolt", "house", "wrench.and.screwdriver", "star", "heart", "tag", "exclamationmark.triangle", "wifi", "desktopcomputer", "cable.connector", "battery.100percent", "leaf", "flame", "drop", "lock", "key", "trash", "folder", "scissors", "lightbulb", "car", "bicycle"]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Choose an Icon").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            TextField("Search icons", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 14) {
                    ForEach(icons.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { icon in
                        Button {
                            if store.selected?.kind == .icon { store.edit { $0.content = icon } }
                            else { store.add(.icon, content: icon) }; dismiss()
                        } label: {
                            VStack { Image(systemName: icon).font(.title); Text(icon).font(.caption2).lineLimit(1) }
                                .frame(width: 90, height: 65)
                        }
                    }
                }
            }
        }.padding(24).frame(width: 520, height: 380)
    }
}
