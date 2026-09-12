import SwiftUI

/// Small panel that renders an on-brand badge from a glyph + label + colour, with a
/// live preview. Hands back PNG data when the user accepts it.
struct BadgeGeneratorSheet: View {
    let initialGlyph: String
    let initialLabel: String
    let onDone: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var glyph: String
    @State private var label: String
    @State private var outline: Color
    @State private var fill: Color

    init(initialGlyph: String, initialLabel: String, onDone: @escaping (Data) -> Void) {
        self.initialGlyph = initialGlyph
        self.initialLabel = initialLabel
        self.onDone = onDone
        _glyph = State(initialValue: initialGlyph)
        _label = State(initialValue: initialLabel)
        // Defaults echo the real Illustrator badge: amber outline + dark maroon fill.
        let amber = NSColor(deviceRed: 0.96, green: 0.65, blue: 0.14, alpha: 1)
        let maroon = NSColor(deviceRed: 0.17, green: 0.04, blue: 0.04, alpha: 1)
        _outline = State(initialValue: Color(amber))
        _fill = State(initialValue: Color(maroon))
    }

    private var preview: NSImage? {
        BadgeGenerator.makeImage(glyph: glyph, label: label,
                                 outline: NSColor(outline), fill: NSColor(fill), side: 256)
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
                    field("Glyph (1–3 letters)", "Ai", $glyph)
                    field("Label", "AI", $label)
                    ColorPicker("Outline & glyph", selection: $outline, supportsOpacity: false)
                    ColorPicker("Inner fill", selection: $fill, supportsOpacity: false)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use badge") {
                    if let data = BadgeGenerator.makePNG(glyph: glyph, label: label,
                                                         outline: NSColor(outline), fill: NSColor(fill)) {
                        onDone(data)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(glyph.trimmingCharacters(in: .whitespaces).isEmpty
                          && label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
