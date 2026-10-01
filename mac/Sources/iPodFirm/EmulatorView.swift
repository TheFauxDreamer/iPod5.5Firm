import AppKit
import SwiftUI

struct EmulatorView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var emu: EmulatorManager

    var body: some View {
        Form {
            Section {
                Text("Try your customised firmware in an emulated iPod 5.5G before flashing a real one. It shows the screen and responds to the click wheel; there's no sound or USB.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let v = emu.installedVersion {
                        Label("ipod-emulator \(v) is installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("The emulator isn't installed yet", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    }
                    Spacer()
                    Button(emu.installedVersion == nil ? "Install Emulator" : "Update Emulator") { emu.install() }
                        .disabled(emu.installing)
                }
            } header: { Text("Emulator") }

            if emu.installing || !emu.log.isEmpty {
                Section {
                    if emu.installing { ProgressView().controlSize(.small) }
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(emu.log).font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            Color.clear.frame(height: 1).id("end")
                        }
                        .frame(height: 160)
                        .onChange(of: emu.log) { _, _ in proxy.scrollTo("end") }
                    }
                } header: { Text("Installer output") } footer: {
                    Text("Builds siggifly/ipod-emulator from source (Rust is installed into your home folder if needed). First build takes a few minutes.")
                }
            }

            Section {
                HStack {
                    Button("Run in Emulator") { model.runInEmulator(emu) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.editor == nil || !emu.toolsReady)
                    Button("Export .ipsw…") { model.exportIPSW() }.disabled(model.editor == nil)
                    if model.editor == nil { Text("Open a firmware first.").foregroundStyle(.secondary) }
                }
                if let when = emu.lastRun {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Booting your firmware in the emulator as “\(EmulatorManager.deviceName)” (started \(when.formatted(date: .omitted, time: .shortened))).").bold()
                            Text("It cold-boots, so expect a white screen for a minute or so — that's normal. Re-run after every change: each run rebuilds the emulator's drive from your latest edits.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: { Image(systemName: "play.circle.fill").foregroundStyle(.green) }
                }
                Text("Run in Emulator quits the emulator if it's open, builds its drive from your edited firmware, selects the “\(EmulatorManager.deviceName)” device and starts it from cold. Your other emulator devices are left as they are.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } header: { Text("Test your firmware") }
        }
        .formStyle(.grouped)
        .onAppear { emu.refresh() }
    }
}

struct Step: View {
    let n: Int
    let text: String
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "\(n).circle.fill") }
    }
}
