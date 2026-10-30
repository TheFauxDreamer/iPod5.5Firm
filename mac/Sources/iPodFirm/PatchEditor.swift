import SwiftUI
import AppKit
import IPodFWKit

// The New Patch and Edit Patch sheet. It writes the text of patch.json, so that the owner does not
// write the keys by hand. PatchLibrary.create and PatchLibrary.edit do the work.

/// The sheet: a new patch (`patch` is nil), or an edit of one user patch.
struct PatchEditorState: Identifiable {
    let id = UUID()
    var draft: PatchDraft
    let patch: PatchInfo?
}

struct PatchEditorSheet: View {
    @EnvironmentObject var model: AppModel
    let state: PatchEditorState
    @State private var draft: PatchDraft
    /// true: the owner typed a name. The name then does not follow the title.
    @State private var nameEdited = false
    private let hasCompiler: Bool

    init(state: PatchEditorState) {
        self.state = state
        hasCompiler = PatchLibrary.hasCompiler()
        var d = state.draft
        if state.patch == nil && !hasCompiler { d.kind = .bytes }
        _draft = State(initialValue: d)
    }

    var isNew: Bool { state.patch == nil }

    var problems: [String] {
        var r = draft.problems(existing: model.patches, editing: state.patch)
        if !draft.symbol.isEmpty, NSImage(systemSymbolName: draft.symbol, accessibilityDescription: nil) == nil {
            r.append("macOS has no SF Symbol with the name \"\(draft.symbol)\".")
        }
        return r
    }

    /// One item on each line.
    func lines(_ path: WritableKeyPath<PatchDraft, [String]>) -> Binding<String> {
        Binding(get: { draft[keyPath: path].joined(separator: "\n") },
                set: { draft[keyPath: path] = $0.components(separatedBy: "\n") })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SymbolTile(symbol: validSymbol(draft.symbol), tint: .accentColor, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isNew ? "New Patch" : "Edit \(state.patch?.spec.displayTitle ?? "")").font(.title2.weight(.semibold))
                    Text(isNew ? "iPodFirm writes patch.json for you. Then you add the code or the byte changes."
                               : "iPodFirm saves the text in patch.json and increases the version.")
                        .foregroundStyle(.secondary)
                }
            }
            Form {
                Section {
                    TextField("Title", text: $draft.title, prompt: Text("For example: Sleep Now"))
                    TextField("Name", text: Binding(get: { draft.name }, set: { draft.name = $0; nameEdited = true }))
                        .monospaced().disabled(!isNew)
                    TextField("Summary", text: $draft.summary, prompt: Text("One line for the list of patches"))
                    Picker("Group", selection: $draft.category) {
                        ForEach(PatchList.groups, id: \.0) { key, title in Text(title).tag(key) }
                    }
                    HStack {
                        TextField("SF Symbol", text: $draft.symbol, prompt: Text("For example: moon.zzz"))
                        Image(systemName: validSymbol(draft.symbol)).frame(width: 22)
                    }
                    if isNew {
                        Picker("Type", selection: $draft.kind) {
                            Text("C Code").tag(PatchDraft.Kind.code)
                            Text("Byte Changes").tag(PatchDraft.Kind.bytes)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!hasCompiler)
                        if !hasCompiler {
                            Text("To write C code, install the Xcode command line tools. Enter xcode-select --install in Terminal.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("What It Does") {
                    TextField("Description", text: $draft.description, prompt: Text("One or two short sentences"), axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Details", text: lines(\.details), prompt: Text("One change on each line"), axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("More") {
                    TextField("You Need", text: lines(\.requires), prompt: Text("One item on each line"), axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Good to Know", text: lines(\.notes), prompt: Text("One item on each line"), axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Caution", text: $draft.caution, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .formStyle(.grouped)
            .frame(height: 470)
            ForEach(problems, id: \.self) { p in
                Label(p, systemImage: "xmark.octagon.fill").labelStyle(StatusLabelStyle(tint: .red)).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.patchEditor = nil }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Make Patch" : "Save as Version \(PatchVersion.next(after: state.patch?.spec.version))") {
                    model.savePatchEditor(state, draft)
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(!problems.isEmpty || model.busy != nil)
            }
        }
        .padding(22)
        .frame(width: 560)
        .onChange(of: draft.title) { _, title in
            if isNew && !nameEdited { draft.name = PatchDraft.name(fromTitle: title) }
        }
    }
}
