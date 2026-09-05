import SwiftUI
import UniformTypeIdentifiers

/// One sheet for both creating and editing a badge rule. A clickable badge "well" at
/// the top swaps the icon (bundled badge or your own uploaded image); below are the
/// name and the file extensions it matches.
///
/// `editing == nil` → create mode (adds a new rule at the top = highest priority).
/// `editing != nil` → edit mode (prefilled; Save updates in place; Delete removes it).
struct RuleEditorSheet: View {
    @ObservedObject var model: BadgeRulesModel
    let editing: BadgeRule?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var extensionsText: String
    @State private var badgeAsset: String?
    @State private var isCustom: Bool
    @State private var showingChooser = false
    @State private var importing = false
    @State private var importError: String?

    init(model: BadgeRulesModel, editing: BadgeRule? = nil) {
        self.model = model
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _extensionsText = State(initialValue: editing?.fileExtensions.joined(separator: " ") ?? "")
        _badgeAsset = State(initialValue: editing?.badgeAsset)
        _isCustom = State(initialValue: editing?.isCustomImage ?? false)
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit format" : "New format")
                .font(.title3.bold())

            HStack(alignment: .top, spacing: 16) {
                badgeWell
                VStack(alignment: .leading, spacing: 12) {
                    field("Name", "e.g. After Effects", $name)
                    VStack(alignment: .leading, spacing: 4) {
                        field("File extensions", "aep aepx", $extensionsText)
                        if !conflicts.isEmpty {
                            Label("Also used by another rule: \(conflicts.map { ".\($0)" }.joined(separator: " ")) — the higher rule wins",
                                  systemImage: "arrow.up.arrow.down")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }

            Divider()
            footer
        }
        .padding(20)
        .frame(width: 420)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.png, .jpeg, .image],
                      allowsMultipleSelection: false) { handleImport($0) }
    }

    // MARK: - Badge well + chooser

    private var badgeWell: some View {
        Button { showingChooser = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.quaternary)
                if let asset = badgeAsset,
                   let img = BadgeImageLoader.image(for: previewRule(asset)) {
                    Image(nsImage: img).resizable().scaledToFit().padding(10)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus").font(.title2)
                        Text("Choose").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(.background))
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .help("Click to change the badge icon")
        .popover(isPresented: $showingChooser, arrowEdge: .bottom) { chooser }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bundled badges").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                ForEach(BadgeRule.bundledBadgeAssets, id: \.self) { asset in
                    Button {
                        badgeAsset = asset; isCustom = false; showingChooser = false
                    } label: {
                        badgeThumb(asset: asset, custom: false)
                            .frame(width: 44, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected(asset, false) ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            Button {
                showingChooser = false; importing = true
            } label: {
                Label("Upload image…", systemImage: "square.and.arrow.up")
            }
            Text("PNG or JPG, up to \(Int(BadgeStore.maxBadgeImageMB)) MB. Large images are scaled to \(Int(BadgeStore.badgeStorageSide)) px.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isEditing {
                Button(role: .destructive) {
                    if let editing { model.delete(editing) }
                    dismiss()
                } label: { Label("Delete", systemImage: "trash") }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isEditing ? "Save" : "Add") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
        }
    }

    // MARK: - Helpers

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func previewRule(_ asset: String) -> BadgeRule {
        BadgeRule(name: "", fileExtensions: [], badgeAsset: asset, isCustomImage: isCustom)
    }

    private func badgeThumb(asset: String, custom: Bool) -> some View {
        Group {
            if let img = BadgeImageLoader.image(for:
                BadgeRule(name: "", fileExtensions: [], badgeAsset: asset, isCustomImage: custom)) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Image(systemName: "photo")
            }
        }
    }

    private func isSelected(_ asset: String, _ custom: Bool) -> Bool {
        badgeAsset == asset && isCustom == custom
    }

    private var parsedExtensions: [String] {
        let raw = extensionsText
            .split(whereSeparator: { ", ;\n\t".contains($0) })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }
            .filter { !$0.isEmpty }
        return Array(Set(raw)).sorted()
    }

    private var conflicts: [String] {
        model.conflictingExtensions(parsedExtensions, excluding: editing?.id)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !parsedExtensions.isEmpty
            && badgeAsset != nil
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(err) = result { importError = err.localizedDescription }
            return
        }
        do {
            let stored = try model.importCustomBadge(from: url)
            badgeAsset = stored; isCustom = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func save() {
        guard let badgeAsset, isValid else { return }
        let rule = BadgeRule(
            id: editing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            fileExtensions: parsedExtensions,
            badgeAsset: badgeAsset,
            isCustomImage: isCustom,
            isEnabled: editing?.isEnabled ?? true
        )
        if isEditing { model.update(rule) } else { model.addRule(rule) }
        dismiss()
    }
}
