import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LabelCore

struct EditorView: View {
    @ObservedObject var store: EditorStore
    @State private var printSettings = false
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mediaAndInsert
            Divider()
            HStack(spacing: 0) {
                if store.isA4 && !store.sheetOverview {
                    SheetNavigator(store: store).frame(width: 168)
                    Divider()
                }
                LabelCanvas(store: store).frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                ObjectInspector(store: store).frame(width: 280)
                    .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1180, minHeight: 720)
        .sheet(isPresented: $store.iconPicker) { IconPicker(store: store) }
        .sheet(isPresented: $store.copySheet) { CopyLabelSheet(store: store) }
        .sheet(item: $store.cropImageItem) { item in ImageCropSheet(store: store, item: item) }
        .task { await store.refreshPrinter() }
    }
    private func iconButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 28) }
            .buttonStyle(.borderless).help(title).accessibilityLabel(title)
    }
    private var header: some View {
        HStack(spacing: 8) {
            iconButton("New", "doc.badge.plus", action: store.newLabel)
            iconButton("Open", "folder", action: store.open)
            iconButton("Save", "square.and.arrow.down", action: { store.save() })
            Divider().frame(height: 22)
            iconButton("Undo", "arrow.uturn.backward", action: store.undo).disabled(!store.history.canUndo)
            iconButton("Redo", "arrow.uturn.forward", action: store.redo).disabled(!store.history.canRedo)
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                TextField("Label name", text: Binding(get: { store.document.name }, set: { value in store.change { $0.name = value } }))
                    .textFieldStyle(.plain).multilineTextAlignment(.center).font(.headline).frame(width: 160)
                Text(store.dirty ? "Edited" : store.fileURL == nil ? "New document" : "Saved")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Circle().fill(store.connected ? Color.green : .gray).frame(width: 7, height: 7)
            Picker("Printer", selection: Binding(get: { store.printerName }, set: store.choosePrinter)) {
                Text("PT-2430PC").tag("PT-2430PC")
                Text("A4 / PDF").tag("A4 / PDF")
                ForEach(store.systemPrinters, id: \.self) { name in Text(name).tag(name) }
            }.labelsHidden().frame(width: 170)
            iconButton("Detect printer again", "arrow.clockwise") { Task { await store.refreshPrinter() } }.disabled(store.busy)
            Button { printSettings.toggle() } label: { Image(systemName: "slider.horizontal.3").frame(width: 28, height: 28) }
                .buttonStyle(.borderless).help("Print settings").accessibilityLabel("Print settings")
                .popover(isPresented: $printSettings) { PrintSettingsPanel(store: store).padding(18).frame(width: 370) }
            Button(store.isA4 ? "PDF" : "PNG", action: store.export).help("Export at actual size").disabled(store.preview == nil)
            Button { Task { await store.printLabel() } } label: { Label(store.isA4 ? "Print…" : "Print", systemImage: "printer").frame(minWidth: 70) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy || store.preview == nil)
        }.padding(.horizontal, 12).padding(.vertical, 8)
    }
    private var mediaAndInsert: some View {
        HStack(spacing: 8) {
            Button { store.add(.text) } label: { Label("Text", systemImage: "textformat") }
            Button { store.importImage() } label: { Label("Image", systemImage: "photo") }
            Button { store.add(.qr) } label: { Label("QR", systemImage: "qrcode") }
            Menu {
                Button("Paste Image", action: { store.pasteImage() })
                Button("Icon") { store.iconPicker = true }
            } label: { Image(systemName: "plus.circle") }.menuStyle(.borderlessButton).fixedSize().help("More insert tools")
            Divider().frame(height: 22)
            if let sheet = store.document.sheet {
                Picker("Template", selection: Binding(get: { store.document.sheet?.templateID ?? "blank" }, set: store.setTemplate)) {
                    ForEach(SheetTemplate.all) { template in Text(template.title).tag(template.id) }
                }.labelsHidden().frame(width: 215)
                Text("\(sheet.template.width.formatted()) × \(sheet.template.height.formatted()) mm")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("Label \(sheet.activeIndex + 1) / \(sheet.template.count)").font(.caption).monospacedDigit()
                Button(store.sheetOverview ? "Edit Label" : "Sheet Overview") {
                    if store.sheetOverview { store.focusLabel(sheet.activeIndex) }
                    else { store.endGesture(); store.sheetOverview = true; store.selection = nil; store.fit = true }
                }
                Menu {
                    Button("Choose Destinations…") { store.endGesture(); store.copySheet = true }
                    Button("Copy to All Empty Labels", action: store.copyToEmptyLabels)
                    Divider()
                    Button("Clear This Label", role: .destructive, action: store.clearActiveLabel)
                } label: { Label("Copy Label", systemImage: "square.on.square") }
                  primaryAction: { store.endGesture(); store.copySheet = true }
                    .disabled(store.document.items.isEmpty || sheet.template.count < 2)
            } else {
                Picker("Tape", selection: Binding(get: { store.document.tapeMM }, set: store.resizeTape)) {
                    ForEach([6.0, 9, 12, 18, 24], id: \.self) { Text("\(Int($0)) mm").tag($0) }
                }.frame(width: 125)
                Picker("Length mode", selection: Binding(get: { store.document.autoLength }, set: store.setAutoLength)) {
                    Text("Auto").tag(true); Text("Fixed").tag(false)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 114)
                TextField("Length", value: Binding(get: { store.document.effectiveLengthMM }, set: store.setLength),
                          format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder).frame(width: 58).disabled(store.document.autoLength)
                Text("mm").foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(store.copies) \(store.copies == 1 ? "copy" : "copies") · \(store.cut ? "Auto Cut" : "No Cut")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.controlSize(.regular).padding(.horizontal, 14).padding(.vertical, 8)
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
