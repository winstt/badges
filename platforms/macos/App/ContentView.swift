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
    @State private var editor: Editor?
    @State private var adobeInstalled = false
    @AppStorage("adobeWarningDismissed") private var adobeDismissed = false

    /// What the rule-editor sheet is doing right now.
    private enum Editor: Identifiable {
        case create
        case edit(BadgeRule)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let rule): return rule.id.uuidString
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if adobeInstalled && !adobeDismissed {
                Divider()
                adobeBanner
            }
            Divider()
            List {
                ForEach(model.orderedCategories, id: \.self) { category in
                    Section {
                        if !model.isCollapsed(category) {
                            ForEach(model.rules(in: category)) { rule in
                                ruleRow(rule)
                            }
                        }
                    } header: {
                        categoryHeader(category)
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            footer
        }
        .sheet(item: $editor) { which in
            switch which {
            case .create: RuleEditorSheet(model: model)
            case .edit(let rule): RuleEditorSheet(model: model, editing: rule)
            }
        }
        .onAppear { adobeInstalled = AdobeConflict.adobeInstalled() }
    }

    /// Warns when Adobe Creative Cloud is installed: its Core Sync Finder extension can
    /// hog the badge slot and hide ours. We can't disable it for the user from inside
    /// the sandbox, so we deep-link them to the toggle.
    private var adobeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Adobe Creative Cloud can hide your badges")
                    .font(.subheadline.weight(.semibold))
                Text("Its “Core Sync” Finder extension takes over the badge slot. Turn it off under Finder extensions, then relaunch Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Open Finder Extensions…") { AdobeConflict.openExtensionSettings() }
                        .controlSize(.small)
                    Button("Recheck") { adobeInstalled = AdobeConflict.adobeInstalled() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                adobeDismissed = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
    }

    /// A collapsible category section header: chevron + name + rule count.
    private func categoryHeader(_ category: String) -> some View {
        Button { model.toggleCollapsed(category) } label: {
            HStack(spacing: 6) {
                Image(systemName: model.isCollapsed(category) ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(category).font(.subheadline.weight(.semibold))
                Text("\(model.rules(in: category).count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func ruleRow(_ rule: BadgeRule) -> some View {
        HStack(spacing: 8) {
            reorderControls(rule)
            BadgeRuleRow(rule: rule, model: model)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editor = .edit(rule) }
        .contextMenu {
            Button { editor = .edit(rule) } label: { Label("Edit…", systemImage: "pencil") }
            Button { model.promote(rule) } label: { Label("Move up", systemImage: "arrow.up") }
            Button { model.demote(rule) } label: { Label("Move down", systemImage: "arrow.down") }
            Divider()
            Button(role: .destructive) { model.delete(rule) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// Explicit up/down buttons are the reliable way to reorder priority within a
    /// category (macOS `.onMove` drag is flaky).
    private func reorderControls(_ rule: BadgeRule) -> some View {
        VStack(spacing: 1) {
            Button { model.promote(rule) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(model.isFirstInCategory(rule))
            Button { model.demote(rule) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(model.isLastInCategory(rule))
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Badges")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                Text("Top of the list wins when a file matches more than one")
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
                editor = .create
            } label: {
                Label("New format", systemImage: "plus")
            }
            Button("Reset to defaults") { model.resetToDefaults() }
            Spacer()
            Text("Double-click to edit · drag to reorder · right-click for more")
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
                Image(badge: img)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
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
