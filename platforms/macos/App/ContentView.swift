import SwiftUI

// MARK: - Menu-bar panel (primary UI)

/// The dropdown that opens from the menu-bar "B". Master switch up top, a scroll of
/// per-badge on/off toggles below, actions at the bottom.
struct MenuPanel: View {
    @ObservedObject var model: BadgeRulesModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            badgeList
            Divider()
            panelFooter
        }
        .frame(width: 300)
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            // Inside the app we can show the brand: the red "B" app icon.
            if let img = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                Image(nsImage: img)
                    .resizable().scaledToFit()
                    .frame(width: 24, height: 24)
                    .opacity(model.badgingEnabled ? 1 : 0.5)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Badges").font(.headline)
                Text(model.badgingEnabled
                     ? "\(model.enabledCount) of \(model.rules.count) active"
                     : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $model.badgingEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(12)
    }

    private var badgeList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.rules) { rule in
                    BadgeRuleRow(rule: rule, model: model, compact: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    Divider().padding(.leading, 52)
                }
            }
        }
        .frame(maxHeight: 260)
        // Dim the whole list while paused so it's clear toggles are per-badge
        // fine-tuning of an active feature.
        .opacity(model.badgingEnabled ? 1 : 0.45)
        .disabled(!model.badgingEnabled)
    }

    private var panelFooter: some View {
        HStack {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Manage…", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .font(.caption)

            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .help("Repaint badges in the frontmost Finder window")

            Spacer()

            // TODO: point at the real donate page once the repo/sponsors is live.
            Link(destination: URL(string: "https://github.com/sponsors")!) {
                Image(systemName: "heart.fill")
            }
            .help("Donate")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit Badges")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Manager window (kept for the fuller rule management next)

struct ContentView: View {
    @ObservedObject var model: BadgeRulesModel
    @State private var addingFormat = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                ForEach(model.rules) { rule in
                    BadgeRuleRow(rule: rule, model: model)
                        .contextMenu {
                            Button(role: .destructive) {
                                model.delete(rule)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.inset)
            Divider()
            footer
        }
        .sheet(isPresented: $addingFormat) {
            AddFormatSheet(model: model)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Badges")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                Text("File-type badges for Finder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Badging on", isOn: $model.badgingEnabled)
                .toggleStyle(.switch)
            // TODO: point at the real donate page once the repo/sponsors is live.
            Link(destination: URL(string: "https://github.com/sponsors")!) {
                Label("Donate", systemImage: "heart.fill")
                    .font(.caption.bold())
            }
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button {
                addingFormat = true
            } label: {
                Label("Add format", systemImage: "plus")
            }
            Button("Reset to defaults") { model.resetToDefaults() }
            Spacer()
            Text("Right-click a row to delete")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }
}

// MARK: - Shared row

struct BadgeRuleRow: View {
    let rule: BadgeRule
    @ObservedObject var model: BadgeRulesModel
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            badgePreview
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(compact ? .callout.weight(.medium) : .body.weight(.medium))
                Text(rule.fileExtensions.map { ".\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Toggle("", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(compact ? .small : .regular)
        }
        .padding(.vertical, compact ? 0 : 4)
    }

    private var badgePreview: some View {
        Group {
            if let img = BadgeImageLoader.image(for: rule) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
        }
        .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
        .opacity(rule.isEnabled ? 1 : 0.4)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { rule.isEnabled }, set: { _ in model.toggle(rule) })
    }
}
