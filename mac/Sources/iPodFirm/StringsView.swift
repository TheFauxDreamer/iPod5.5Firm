import IPodFWKit
import SwiftUI

struct StringRow: Identifiable {
    var id: String { key }
    let key: String
    let original: String
}

struct StringsView: View {
    @EnvironmentObject var model: AppModel
    @State private var blockIndex: Int?
    @State private var rows: [StringRow] = []
    @State private var draft: [String: String] = [:]
    @State private var search = ""

    var blocks: [ResourceBlock] { model.editor?.stringBlocks ?? [] }

    func label(_ b: ResourceBlock) -> String {
        let sample = model.editor?.strings(b).first { $0.key == "129" }?.value ?? ""
        let main = b.index == model.editor?.mainIndex
        return "\(main ? "Main (English)" : "Language block \(b.index)") — “\(sample)”"
    }

    var changes: [String: String] { draft.filter { k, v in rows.first { $0.key == k }?.original != v } }

    var budget: (used: Int, available: Int) {
        guard let ed = model.editor, let i = blockIndex, let b = ed.blocks.first(where: { $0.index == i }) else { return (0, 0) }
        return ed.budget(b, changes)
    }

    var visible: [StringRow] {
        search.isEmpty ? rows : rows.filter {
            $0.key.contains(search) || (draft[$0.key] ?? $0.original).localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Language", selection: $blockIndex) {
                    ForEach(blocks) { b in Text(label(b)).tag(Optional(b.index)) }
                }
                .frame(maxWidth: 380)
                Spacer()
                BudgetGauge(used: budget.used, available: budget.available)
            }
            .padding(10)
            Divider()
            Table(visible) {
                TableColumn("ID") { row in Text(row.key).monospacedDigit().foregroundStyle(.secondary) }
                    .width(min: 50, ideal: 60, max: 80)
                TableColumn("Text") { row in
                    TextField("", text: Binding(
                        get: { draft[row.key] ?? row.original },
                        set: { draft[row.key] = $0 }))
                    .textFieldStyle(.plain)
                    .foregroundStyle((draft[row.key] ?? row.original) != row.original ? Color.accentColor : .primary)
                }
            }
            Divider()
            HStack {
                Text("The text cannot use more space than the language uses now. To make one string longer, make other strings shorter.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Revert") { draft = [:] }.disabled(changes.isEmpty)
                Button("Apply \(changes.count) Change\(changes.count == 1 ? "" : "s")") { apply() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(changes.isEmpty || budget.used > budget.available)
            }
            .padding(10)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Text or ID")
        .onAppear {
            if blockIndex == nil { blockIndex = model.editor?.mainIndex }
            reload()
        }
        .onChange(of: blockIndex) { _, _ in reload() }
        .onChange(of: model.revision) { _, _ in reload() }
        .onChange(of: changes.count) { _, count in model.pendingStringChanges = count }
        .onDisappear { model.pendingStringChanges = 0 }
    }

    func reload() {
        guard let ed = model.editor, let i = blockIndex, let b = ed.blocks.first(where: { $0.index == i }) else { rows = []; return }
        rows = ed.strings(b).map { StringRow(key: $0.key, original: $0.value) }
        draft = [:]
    }

    func apply() {
        guard let i = blockIndex else { return }
        if model.applyStrings(blockIndex: i, changes) { reload() }
    }
}

struct BudgetGauge: View {
    let used: Int
    let available: Int
    var body: some View {
        let over = used > available
        HStack(spacing: 8) {
            Gauge(value: Double(min(used, available)), in: 0...Double(max(available, 1))) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(over ? .red : .accentColor)
                .frame(width: 120)
            Text(over ? "\(used - available) bytes over" : "\(available - used) bytes free")
                .font(.caption.monospacedDigit())
                .foregroundStyle(over ? .red : .secondary)
        }
        .help("Space used by this language's text: \(used) of \(available) bytes")
    }
}
