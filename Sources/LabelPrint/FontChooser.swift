import SwiftUI
import AppKit
import LabelCore

/// Font names and the current label text are drawn with the candidate font.
/// Browsing does not mutate the document or fill its undo history.
struct FontChooser: View {
    let item: LabelItem
    let onChoose: (String?) -> Void
    @State private var presented = false
    @State private var query = ""
    @State private var candidate = "System"
    private let families = ["System"] + NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }
    private var matches: [String] {
        families.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }
    private func font(_ family: String, size: Double) -> Font {
        var preview = item
        preview.fontName = family == "System" ? nil : family
        return Font(preview.resolvedFont(ofSize: size))
    }
    var body: some View {
        HStack {
            Text("Font")
            Spacer()
            Button {
                query = ""; candidate = item.fontName ?? "System"; presented = true
            } label: {
                HStack {
                    Text(item.fontName ?? "System").lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }.frame(maxWidth: .infinity)
            }.accessibilityLabel("Choose font with preview")
                .popover(isPresented: $presented) {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Search fonts", text: $query).textFieldStyle(.roundedBorder)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(candidate).font(.caption).foregroundStyle(.secondary)
                            Text(item.content.isEmpty ? "Aa Bb 123 字体预览" : item.content)
                                .font(font(candidate, size: 26)).lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
                        }.padding(12).background(.white).foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 2) {
                                    ForEach(matches, id: \.self) { family in
                                        Button {
                                            onChoose(family == "System" ? nil : family)
                                            presented = false
                                        } label: {
                                            HStack {
                                                Image(systemName: family == (item.fontName ?? "System") ? "checkmark" : "circle")
                                                    .font(.caption).frame(width: 16)
                                                Text(family).font(font(family, size: 16)).lineLimit(1)
                                                Spacer()
                                                Text("Aa 123").font(font(family, size: 18))
                                            }.padding(8).contentShape(Rectangle())
                                                .background(candidate == family ? Color.accentColor.opacity(0.12) : .clear)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        }.buttonStyle(.plain).id(family)
                                            .onHover { if $0 { candidate = family } }
                                    }
                                }
                            }.frame(height: 290)
                                .onAppear { proxy.scrollTo(item.fontName ?? "System", anchor: .center) }
                        }
                        if matches.isEmpty { Text("No matching fonts").foregroundStyle(.secondary) }
                    }.padding(14).frame(width: 370)
                }
        }
    }
}
