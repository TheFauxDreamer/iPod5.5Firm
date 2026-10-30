import SwiftUI
import AppKit
import IPodFWKit

// The Code section of a user patch in the Patches pane: the C file, the firmware functions, the
// hooks and the byte changes. The owner types or pastes the code, clicks Check Code and then Save.
// The changes stay in AppModel.codeDrafts until Save or Revert, also if the owner selects another patch.

extension AppModel {
    /// The code in the editor: the draft, or the saved code.
    func code(for patch: PatchInfo) -> PatchCode { codeDrafts[patch.spec.name] ?? PatchCode(patch: patch) }

    func setCode(_ code: PatchCode, for patch: PatchInfo) {
        codeDrafts[patch.spec.name] = code == PatchCode(patch: patch) ? nil : code
    }

    /// The osos of the open firmware, if it is the firmware of the patch. Check Code and "Read from
    /// Firmware" use it for the `expect` values.
    func firmwareOSOS(for patch: PatchInfo) -> [UInt8]? {
        guard let editor, editor.originalOSOSHash == patch.spec.osos_sha256 else { return nil }
        return editor.osos
    }

    func checkCode(_ patch: PatchInfo) async {
        let library = Self.patchLibrary, code = code(for: patch), osos = firmwareOSOS(for: patch)
        let result = try? await work("Checking the code…") { library.check(patch, code, osos: osos) }
        codeChecks[patch.spec.name] = result
    }

    /// Check the code. If it has no problems, write it into the patch and increase the version.
    func saveCode(_ patch: PatchInfo) async {
        let library = Self.patchLibrary, code = code(for: patch), osos = firmwareOSOS(for: patch)
        do {
            let result = try await work("Checking the code…") { library.check(patch, code, osos: osos) }
            codeChecks[patch.spec.name] = result
            guard result.isOK else { return }
            let version = try await work("Saving the patch…") { try library.saveCode(patch, code) }
            codeDrafts[patch.spec.name] = nil
            reloadPatches()
            if enabledPatches.contains(patch.spec.name) {
                alert = AlertInfo(title: "Patch Saved",
                                  message: "The patch is now version \(version). Flash the iPod again to put the new code on it.")
            }
        } catch { fail("Cannot Save the Patch", error) }
    }

    func revertCode(_ patch: PatchInfo) {
        codeDrafts[patch.spec.name] = nil
        codeChecks[patch.spec.name] = nil
    }
}

/// The sections of the code editor. Only for a user patch.
struct PatchCodeSections: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var code: Binding<PatchCode> {
        Binding(get: { model.code(for: patch) }, set: { model.setCode($0, for: patch) })
    }
    var check: PatchCodeCheck? { model.codeChecks[patch.spec.name] }
    var changed: Bool { model.codeDrafts[patch.spec.name] != nil }
    var osos: [UInt8]? { model.firmwareOSOS(for: patch) }
    var isCode: Bool { code.wrappedValue.source != nil }

    var body: some View {
        if isCode {
            Section {
                CodeTextView(text: Binding(get: { code.wrappedValue.source ?? "" }, set: { code.wrappedValue.source = $0 }))
                    .frame(minHeight: 320)
            } header: {
                Text("C Code")
            } footer: {
                FormFooter("Type or paste the C code. The code has no C library: use the functions of the firmware. iPodFirm compiles it for the ARM7TDMI CPU of the iPod.")
            }
            symbolsSection
            hooksSection
        } else if FileManager.default.fileExists(atPath: patch.folder.appendingPathComponent(Patcher.objectFile).path) {
            Section("C Code") {
                Text("This patch has only compiled code (patch.o) and no C file. You cannot change its code in iPodFirm.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        bytesSection
        actionsSection
    }

    /// A binding to one item of a list. The bounds check prevents a crash while a row is removed.
    func item<T>(_ path: WritableKeyPath<PatchCode, [T]>, _ i: Int, empty: T) -> Binding<T> {
        Binding(get: { let a = code.wrappedValue[keyPath: path]; return i < a.count ? a[i] : empty },
                set: { v in if i < code.wrappedValue[keyPath: path].count { code.wrappedValue[keyPath: path][i] = v } })
    }

    // MARK: sections

    var symbolsSection: some View {
        Section {
            ForEach(code.wrappedValue.symbols.indices, id: \.self) { i in
                let s = item(\.symbols, i, empty: PatchCode.Symbol())
                HStack {
                    TextField("Name", text: s.name, prompt: Text("fw_example")).monospaced()
                    TextField("Address", text: s.address, prompt: Text("0x1d83fc")).monospaced().frame(width: 120)
                    RemoveButton { code.wrappedValue.symbols.remove(at: i) }
                }
                .labelsHidden()
            }
            Button("Add Function") { code.wrappedValue.symbols.append(.init()) }
        } header: {
            Text("Firmware Functions")
        } footer: {
            FormFooter("Each name is a function or data of the firmware that the C code declares. The address is the osos offset. docs/firmware-functions.md lists the known addresses.")
        }
    }

    var hooksSection: some View {
        Section {
            ForEach(code.wrappedValue.hooks.indices, id: \.self) { i in
                let hook = item(\.hooks, i, empty: PatchSpec.Hook(kind: "bl", at: "", expect: "", to: ""))
                HStack {
                    Picker("Kind", selection: hook.kind) {
                        Text("bl").tag("bl"); Text("b").tag("b"); Text("word").tag("word")
                    }
                    .frame(width: 80)
                    TextField("At", text: hook.at, prompt: Text("at")).monospaced()
                    TextField("Expect", text: hook.expect, prompt: Text("expect")).monospaced()
                    ReadButton(enabled: osos != nil) {
                        if let osos, let w = PatchCode.word(at: hook.at.wrappedValue, in: osos) { hook.expect.wrappedValue = w }
                    }
                    TextField("To", text: hook.to, prompt: Text("to")).monospaced()
                    Menu {
                        ForEach(check?.functions ?? [], id: \.self) { f in Button(f) { hook.to.wrappedValue = f } }
                    } label: { Image(systemName: "function") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .disabled((check?.functions ?? []).isEmpty)
                    .help("Select a function of the code. Click Check Code first.")
                    .accessibilityLabel("Select Function")
                    RemoveButton { code.wrappedValue.hooks.remove(at: i) }
                }
                .labelsHidden()
            }
            Button("Add Hook") { code.wrappedValue.hooks.append(.init(kind: "bl", at: "", expect: "", to: "")) }
        } header: {
            Text("Hooks")
        } footer: {
            FormFooter("A hook changes one word of the firmware: \"bl\" calls a function of the code, \"b\" jumps to it, and \"word\" replaces a vtable slot. \"Expect\" is the word in the Apple firmware. " + readHint)
        }
    }

    var bytesSection: some View {
        Section {
            ForEach(code.wrappedValue.bytes.indices, id: \.self) { i in
                let b = item(\.bytes, i, empty: PatchSpec.Bytes(at: "", expect: "", value: ""))
                HStack {
                    TextField("At", text: b.at, prompt: Text("at")).monospaced()
                    TextField("Expect", text: b.expect, prompt: Text("expect")).monospaced()
                    ReadButton(enabled: osos != nil) {
                        let count = max(1, b.value.wrappedValue.count / 2)
                        if let osos, let x = PatchCode.bytes(at: b.at.wrappedValue, count: count, in: osos) { b.expect.wrappedValue = x }
                    }
                    TextField("Value", text: b.value, prompt: Text("value")).monospaced()
                    RemoveButton { code.wrappedValue.bytes.remove(at: i) }
                }
                .labelsHidden()
            }
            Button("Add Byte Change") { code.wrappedValue.bytes.append(.init(at: "", expect: "", value: "")) }
        } header: {
            Text("Byte Changes")
        } footer: {
            FormFooter("Each change replaces the bytes \"expect\" at the osos offset \"at\" with the bytes \"value\", for example 0100 → 0001. " + readHint)
        }
    }

    var readHint: String {
        osos == nil ? "Open the Apple firmware 1.3 to read \"expect\" from it."
                    : "The wand button reads \"expect\" from the open firmware."
    }

    var actionsSection: some View {
        Section {
            if let check {
                if check.isOK {
                    Label("The code is correct. Size on iPod: \(PatchSpec.byteText(check.size ?? 0)).", systemImage: "checkmark.circle.fill")
                        .labelStyle(StatusLabelStyle(tint: .green))
                }
                ForEach(check.errors, id: \.self) { e in
                    Label { Text(e).monospaced(e.contains("\n")).textSelection(.enabled) } icon: { Image(systemName: "xmark.octagon.fill") }
                        .labelStyle(StatusLabelStyle(tint: .red)).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                if changed { Text("Changes not saved").foregroundStyle(.secondary) }
                Spacer()
                Button("Revert") { model.revertCode(patch) }.disabled(!changed)
                Button("Check Code") { Task { await model.checkCode(patch) } }.disabled(model.busy != nil)
                Button("Save as Version \(PatchVersion.next(after: patch.spec.version))") { Task { await model.saveCode(patch) } }
                    .buttonStyle(.borderedProminent).disabled(!changed || model.busy != nil)
            }
        }
    }
}

private struct RemoveButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove").accessibilityLabel("Remove")
    }
}

private struct ReadButton: View {
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "wand.and.stars") }.buttonStyle(.borderless)
            .disabled(!enabled).help("Read \"expect\" from the open firmware")
            .accessibilityLabel("Read Expect from Firmware")
    }
}

/// A text view for C code: a monospaced font, and no automatic change of quotes, dashes or spelling.
/// The SwiftUI TextEditor changes " to curly quotes, and the compiler then refuses the code.
struct CodeTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        view.textContainerInset = NSSize(width: 4, height: 6)
        view.string = text
        view.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        let view = scroll.documentView as! NSTextView
        if view.string != text { view.string = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ n: Notification) {
            if let view = n.object as? NSTextView { text.wrappedValue = view.string }
        }
    }
}
