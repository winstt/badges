import SwiftUI
import UniformTypeIdentifiers

/// Glyph thickness options, mapped to Myriad Pro weights (with system fallbacks).
enum GlyphWeight: String, CaseIterable, Identifiable {
    case light = "Light", regular = "Regular", semibold = "Semibold", bold = "Bold", black = "Black"
    var id: String { rawValue }
    var ns: NSFont.Weight {
        switch self {
        case .light: return .light
        case .regular: return .regular
        case .semibold: return .semibold
        case .bold: return .bold
        case .black: return .black
        }
    }
}

/// Small panel that renders an on-brand badge from a glyph (or uploaded logo) + label +
/// colours, with a live preview. Hands back PNG data when the user accepts it.
struct BadgeGeneratorSheet: View {
    let initialGlyph: String
    let initialLabel: String
    let onDone: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var glyph: String
    @State private var label: String
    @State private var outline: Color
    @State private var fill: Color
    @State private var labelColor: Color
    @State private var glyphColor: Color
    @State private var glyphWeight: GlyphWeight = .bold
    @State private var logo: NSImage?
    @State private var importingLogo = false

    init(initialGlyph: String, initialLabel: String, onDone: @escaping (Data) -> Void) {
        self.initialGlyph = initialGlyph
        self.initialLabel = initialLabel
        self.onDone = onDone
        _glyph = State(initialValue: initialGlyph)
        _label = State(initialValue: initialLabel)
        // Defaults echo the real Illustrator badge: amber outline + glyph + dark maroon fill.
        let amber = NSColor(deviceRed: 0.96, green: 0.65, blue: 0.14, alpha: 1)
        let maroon = NSColor(deviceRed: 0.17, green: 0.04, blue: 0.04, alpha: 1)
        _outline = State(initialValue: Color(amber))
        _fill = State(initialValue: Color(maroon))
        _labelColor = State(initialValue: .white)
        _glyphColor = State(initialValue: Color(amber))
    }

    private var preview: NSImage? {
        BadgeGenerator.makeImage(glyph: glyph, label: label,
                                 outline: NSColor(outline), fill: NSColor(fill),
                                 labelColor: NSColor(labelColor), logo: logo,
                                 glyphColor: NSColor(glyphColor), glyphWeight: glyphWeight.ns, side: 256)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Generate badge").font(.title3.bold())

            HStack(alignment: .top, spacing: 20) {
                Group {
                    if let img = preview {
                        Image(badge: img).resizable().interpolation(.high).scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                    }
                }
                .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 12) {
                    // A logo replaces the glyph letters; hide the glyph field while one's set.
                    if logo == nil {
                        field("Glyph (1–3 letters)", "Ai", $glyph)
                    } else {
                        logoRow
                    }
                    field("Label", "AI", $label)
                    ColorPicker("Outline", selection: $outline, supportsOpacity: false)
                    if logo == nil {
                        ColorPicker("Glyph", selection: $glyphColor, supportsOpacity: false)
                        Picker("Glyph weight", selection: $glyphWeight) {
                            ForEach(GlyphWeight.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    ColorPicker("Inner fill", selection: $fill, supportsOpacity: false)
                    ColorPicker("Text", selection: $labelColor, supportsOpacity: false)
                    if logo == nil {
                        Button {
                            importingLogo = true
                        } label: {
                            Label("Upload logo…", systemImage: "photo.badge.plus")
                        }
                        .controlSize(.small)
                    }
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use badge") {
                    if let data = BadgeGenerator.makePNG(glyph: glyph, label: label,
                                                         outline: NSColor(outline), fill: NSColor(fill),
                                                         labelColor: NSColor(labelColor), logo: logo,
                                                         glyphColor: NSColor(glyphColor),
                                                         glyphWeight: glyphWeight.ns) {
                        onDone(data)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(logo == nil
                          && glyph.trimmingCharacters(in: .whitespaces).isEmpty
                          && label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .fileImporter(isPresented: $importingLogo,
                      allowedContentTypes: [.png, .jpeg, .image],
                      allowsMultipleSelection: false) { handleLogoImport($0) }
    }

    /// Shows the picked logo with a button to swap it out for the glyph again.
    private var logoRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Logo").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let logo { Image(badge: logo).resizable().scaledToFit().frame(width: 22, height: 22) }
                Button {
                    logo = nil
                } label: {
                    Label("Remove logo", systemImage: "xmark.circle")
                }
                .controlSize(.small)
            }
        }
    }

    private func handleLogoImport(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let img = NSImage(contentsOf: url) { logo = img }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
