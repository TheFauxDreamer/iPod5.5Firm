import IPodFWKit
import SwiftUI

/// Help > Thanks…: the people who reported problems, supplied fixes or gave ideas.
struct ThanksSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Thanks", systemImage: "heart").font(.title3.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Thanks.sorted) { person in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(person.name).bold()
                                Spacer()
                                if let version = person.version {
                                    Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(person.reason).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let link = person.link {
                                Link(link.absoluteString, destination: link).font(.caption)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
