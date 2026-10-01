import AppKit
import SwiftUI

struct EmulatorView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Text("Try your customised firmware in an emulated iPod 5.5G before flashing a real one. The emulator boots Apple's firmware with screen and click wheel, but has no sound or USB.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Export .ipsw for Emulator…") { model.exportIPSW() }
                        .disabled(model.editor == nil)
                        .buttonStyle(.borderedProminent)
                    if model.editor == nil {
                        Text("Open a firmware first.").foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Test in the emulator") }

            Section {
                Step(n: 1, text: "Download ipod-emulator for macOS and open it. It isn't code-signed: allow it under System Settings → Privacy & Security.")
                Step(n: 2, text: "Click Export .ipsw for Emulator above.")
                Step(n: 3, text: "Drop the exported .ipsw onto the emulator window. It builds a drive from it and boots your firmware.")
                Button("Open ipod-emulator Releases") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/siggifly/ipod-emulator/releases")!)
                }
            } header: { Text("How") }
        }
        .formStyle(.grouped)
    }
}

struct Step: View {
    let n: Int
    let text: String
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "\(n).circle.fill") }
    }
}
