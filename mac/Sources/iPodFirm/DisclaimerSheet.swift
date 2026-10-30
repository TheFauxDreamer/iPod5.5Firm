import AppKit
import SwiftUI

/// The terms that the user must accept before the first use of the app.
enum Disclaimer {
    /// Increase this value after a large change to the text. Then each user must accept the terms again.
    static let version = 1
    static let key = "acceptedDisclaimerVersion"

    static var accepted: Bool { UserDefaults.standard.integer(forKey: key) >= version }
}

/// The disclaimer sheet. At the first launch the user must accept it or quit the app.
/// Help > Show Disclaimer shows it again with only a Close button (`review`).
struct DisclaimerSheet: View {
    let review: Bool
    @Environment(\.dismiss) var dismiss
    @AppStorage(Disclaimer.key) private var acceptedVersion = 0
    @State private var understood = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Before You Use iPodFirm", systemImage: "exclamationmark.triangle").font(.title3.bold())
            Text("WARNING: A change to the firmware can damage your iPod. iPodFirm makes a backup before each flash and has a recovery procedure, but this is not a guarantee.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("• The software comes with no warranty. A flash could make the iPod unusable.")
                Text("• Use the software at your own risk. The author is not responsible for damage to your iPod, or loss of your music.")
                Text("• This is a personal project. The author does not give technical support to each person.")
                Text("• iPodFirm is not affiliated with Apple Inc. Apple and iPod are trademarks of Apple Inc.")
            }
            .fixedSize(horizontal: false, vertical: true)
            if !review {
                Toggle("I understand the risk and I accept these terms.", isOn: $understood)
            }
            HStack {
                Spacer()
                if review {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                } else {
                    Button("Quit") { quit() }
                    Button("Agree") {
                        acceptedVersion = Disclaimer.version
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(!understood)
                }
            }
        }
        .padding(22)
        .frame(width: 500)
    }

    /// AppKit does not quit while a window has an attached sheet. Thus close the sheet first.
    /// The user did not accept the terms, so the Finder patches stay in the queue (`AppDelegate.attach`).
    private func quit() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
    }
}
