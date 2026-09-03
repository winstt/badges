import SwiftUI
import UniformTypeIdentifiers

/// Sheet for creating a new badge rule: a name, the file extensions it matches, and a
/// badge image — either one of the bundled badges or a PNG the user imports.
struct AddFormatSheet: View {
    @ObservedObject var model: BadgeRulesModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var extensionsText = ""
    /// Currently chosen badge: a bundled asset name, or an imported filename.
    @State private var badgeAsset: String?
    @State private var isCustom = false
    @State private var importing = false
    @State private var importError: String?

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add format").font(.title3.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. After Effects", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("File extensions").font(.caption).foregroundStyle(.secondary)
                TextField("aep, aepx", text: $extensionsText)
                    .textFieldStyle(.roundedBorder)
                if !conflicts.isEmpty {
                    Label("Already used: \(conflicts.map { ".\($0)" }.joined(separator: " "))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Badge").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(BadgeRule.bundledBadgeAssets, id: \.self) { asset in
                        badgeTile(asset: asset, custom: false)
                    }
                    if isCustom, let asset = badgeAsset {
                        badgeTile(asset: asset, custom: true)
                    }
                    importTile
                }
            }

            if let importError {
                Text(importError).font(.caption2).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.png, .jpeg, .image],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
    }

    // MARK: - Pieces

    private func badgeTile(asset: String, custom: Bool) -> some View {
        let selected = badgeAsset == asset && isCustom == custom
        return Button {
            badgeAsset = asset; isCustom = custom
        } label: {
            image(asset: asset, custom: custom)
                .resizable().scaledToFit()
                .frame(width: 48, height: 48)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var importTile: some View {
        Button { importing = true } label: {
            VStack(spacing: 2) {
                Image(systemName: "plus")
                Text("Import").font(.caption2)
            }
            .frame(width: 48, height: 48)
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        }
        .buttonStyle(.plain)
        .help("Import your own PNG badge")
    }

    private func image(asset: String, custom: Bool) -> Image {
        let rule = BadgeRule(name: "", fileExtensions: [], badgeAsset: asset, isCustomImage: custom)
        if let ns = BadgeImageLoader.image(for: rule) {
            return Image(nsImage: ns)
        }
        return Image(systemName: "photo")
    }

    // MARK: - Logic

    private var parsedExtensions: [String] {
        let raw = extensionsText
            .split(whereSeparator: { ", ;\n\t".contains($0) })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }
            .filter { !$0.isEmpty }
        return Array(Set(raw)).sorted()
    }

    private var conflicts: [String] { model.conflictingExtensions(parsedExtensions) }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !parsedExtensions.isEmpty
            && badgeAsset != nil
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if let stored = model.importCustomBadge(from: url) {
                badgeAsset = stored; isCustom = true
            } else {
                importError = "Couldn't import that image."
            }
        case .failure(let err):
            importError = err.localizedDescription
        }
    }

    private func save() {
        guard let badgeAsset, isValid else { return }
        let rule = BadgeRule(
            name: name.trimmingCharacters(in: .whitespaces),
            fileExtensions: parsedExtensions,
            badgeAsset: badgeAsset,
            isCustomImage: isCustom
        )
        model.addRule(rule)
        dismiss()
    }
}
