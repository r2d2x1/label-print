import SwiftUI
import LabelCore

struct SheetNavigator: View {
    @ObservedObject var store: EditorStore
    var body: some View {
        if let sheet = store.document.sheet {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LABELS").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(sheet.activeIndex + 1) / \(sheet.template.count)").font(.caption).monospacedDigit()
                }
                GeometryReader { geometry in
                    let scale = geometry.size.width / 210
                    ZStack(alignment: .topLeading) {
                        Color.white
                        if let image = store.sheetPreview {
                            Image(decorative: image, scale: 1).resizable().allowsHitTesting(false)
                        }
                        ForEach(sheet.labels.indices, id: \.self) { index in
                            let rect = sheet.template.rect(at: index)
                            Button { store.focusLabel(index) } label: {
                                Rectangle().fill(index == sheet.activeIndex ? Color.accentColor.opacity(0.12) : .clear)
                                    .overlay(Rectangle().stroke(index == sheet.activeIndex ? Color.accentColor : .gray.opacity(0.3), lineWidth: index == sheet.activeIndex ? 2 : 0.5))
                                    .overlay(alignment: .topLeading) {
                                        Text("\(index + 1)").font(.system(size: 8)).foregroundStyle(.secondary).padding(2)
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        if sheet.printPositions.contains(index) {
                                            Image(systemName: "checkmark").font(.system(size: 7, weight: .semibold)).foregroundStyle(.green).padding(2)
                                        }
                                    }
                                    .frame(width: rect.width * scale, height: rect.height * scale)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).offset(x: rect.minX * scale, y: rect.minY * scale)
                                .accessibilityLabel("Go to label \(index + 1)")
                                .accessibilityValue(index == sheet.activeIndex ? "Current" : "")
                        }
                    }.frame(height: 297 * scale).shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                }.frame(height: 144 * 297 / 210)
                HStack {
                    Button { store.focusLabel(sheet.activeIndex - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(sheet.activeIndex == 0).help("Previous Label").accessibilityLabel("Previous Label")
                    Spacer()
                    Button { store.focusLabel(sheet.activeIndex + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(sheet.activeIndex == sheet.template.count - 1).help("Next Label").accessibilityLabel("Next Label")
                }
                Text("Blue outline: editing\n✓ Selected for printing").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("Click any label to continue editing.").font(.caption).foregroundStyle(.secondary)
            }.padding(12).background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
