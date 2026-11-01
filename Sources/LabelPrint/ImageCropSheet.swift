import SwiftUI
import AppKit
import LabelCore

struct ImageCropSheet: View {
    @ObservedObject var store: EditorStore
    let item: LabelItem
    @Environment(\.dismiss) private var dismiss
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Crop Image").font(.title2.bold())
            Text("Drag a rectangle over the part you want to keep. The label frame stays in place.")
                .font(.callout).foregroundStyle(.secondary)
            if let data = item.imageData, let image = NSImage(data: data) {
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                        Color.black.opacity(0.25)
                            .overlay {
                                Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                                    .mask(Rectangle().frame(width: crop.width * size.width, height: crop.height * size.height)
                                        .position(x: crop.midX * size.width, y: crop.midY * size.height))
                            }
                        Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .frame(width: crop.width * size.width, height: crop.height * size.height)
                            .offset(x: crop.minX * size.width, y: crop.minY * size.height)
                    }.frame(width: size.width, height: size.height).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                            let x1 = min(1, max(0, value.startLocation.x / size.width))
                            let y1 = min(1, max(0, value.startLocation.y / size.height))
                            let x2 = min(1, max(0, value.location.x / size.width))
                            let y2 = min(1, max(0, value.location.y / size.height))
                            crop = CGRect(x: min(x1, x2), y: min(y1, y2), width: max(0.002, abs(x2-x1)), height: max(0.002, abs(y2-y1)))
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(height: 370)
            }
            HStack {
                Button("Reset") { crop = CGRect(x: 0, y: 0, width: 1, height: 1) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply Crop") { store.applyCrop(id: item.id, normalized: crop); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(crop.width < 0.01 || crop.height < 0.01)
            }
        }.padding(22).frame(width: 600)
    }
}
