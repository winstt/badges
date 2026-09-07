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
    @State private var color: Color

    init(initialGlyph: String, initialLabel: String, onDone: @escaping (Data) -> Void) {
        self.initialGlyph = initialGlyph
        self.initialLabel = initialLabel
        self.onDone = onDone
        _glyph = State(initialValue: initialGlyph)
        _label = State(initialValue: initialLabel)
        _color = State(initialValue: Color(red: 0.35, green: 0.22, blue: 0.70))
    }

    private var preview: NSImage? {
        BadgeGenerator.makeImage(glyph: glyph, label: label, color: NSColor(color), side: 256)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Generate badge").font(.title3.bold())

            HStack(alignment: .top, spacing: 20) {
                Group {
                    if let img = preview {
                        Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                    }
                }
                .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 12) {
                    field("Glyph (1–3 letters)", "Ae", $glyph)
                    field("Label", "AEP", $label)
                    ColorPicker("Colour", selection: $color, supportsOpacity: false)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use badge") {
                    if let data = BadgeGenerator.makePNG(glyph: glyph, label: label, color: NSColor(color)) {
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
