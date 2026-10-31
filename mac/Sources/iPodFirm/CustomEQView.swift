import IPodFWKit
import SwiftUI

/// The editor of the patch custom-eq in the Patches pane. The build calculates the filters from the
/// bands (`Patcher.setOptions`). To change the iPod, flash it again.
struct CustomEQView: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo
    @State private var confirmAllBands = false

    var body: some View {
        let bands = model.eqBands(patch)
        let allBands = model.eqUsesAllBands(patch)
        let shown = allBands ? Array(bands.indices) : CustomEQ.standardBands
        let usesPrecut = model.eqUsesPrecut(patch)
        let advanced = model.eqUsesAdvanced(patch)
        Section {
            Picker("View", selection: Binding(get: { advanced }, set: { model.setEQUsesAdvanced(patch, $0) })) {
                Text("Simple").tag(false)
                Text("Advanced").tag(true)
            }
            .pickerStyle(.segmented)
            EQCurve(bands: bands, usesPrecut: usesPrecut).frame(height: 140)
            if advanced {
                ForEach(Array(shown.enumerated()), id: \.element) { row, i in
                    EQBandRow(number: row + 1, band: Binding(get: { bands[i] }, set: { b in
                        var all = bands
                        all[i] = b
                        model.setEQBands(patch, all)
                    }))
                }
            } else {
                ForEach(shown, id: \.self) { i in
                    EQSimpleRow(name: CustomEQ.simpleNames[i], gain: Binding(get: { bands[i].gain }, set: { g in
                        var all = CustomEQ.simple(from: bands)
                        all[i].gain = g
                        model.setEQBands(patch, all)
                    }))
                }
            }
            Toggle("Use All 5 Bands", isOn: Binding(get: { allBands }, set: { on in
                if on { confirmAllBands = true } else { model.setEQUsesAllBands(patch, false) }
            }))
            Toggle("Prevent Clipping", isOn: Binding(get: { usesPrecut }, set: { model.setEQUsesPrecut(patch, $0) }))
            let cut = CustomEQ.precut(bands)
            if usesPrecut, cut < -0.05 {
                LabeledContent("Level", value: String(format: "%.1f dB", cut))
            }
            Button("Reset Bands") { model.setEQBands(patch, advanced ? CustomEQ.defaults : CustomEQ.simpleLayout) }
                .disabled(advanced ? bands == CustomEQ.defaults : bands.allSatisfy { $0.gain == 0 })
            HStack {
                Button("Import EQ…") { model.chooseEQToImport() }
                Button("Export EQ…") { model.exportEQ(patch) }
            }
        } header: {
            Text("Custom EQ")
        } footer: {
            Text("The default is 3 bands. A band at 0 dB is off. Simple keeps only the slider values of Advanced bands. Prevent Clipping lowers the level by the highest boost, so that loud music does not distort. The music then sounds quieter than Flat. Without it, the EQ operates as the Apple presets do, and a strong boost can distort.")
        }
        .confirmationDialog("Use All 5 Bands?", isPresented: $confirmAllBands) {
            Button("I Agree, Use All 5 Bands") { model.setEQUsesAllBands(patch, true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(CustomEQ.allBandsWarning)
        }
    }
}

/// Asks the user before an EQ from a file replaces the bands.
struct EQImportSheet: View {
    @EnvironmentObject var model: AppModel
    let eq: SharedEQ

    /// The file uses more than the 3 standard bands, and the user did not agree yet.
    private var askAllBands: Bool {
        eq.needsAllBands && !(model.eqPatch.map(model.eqUsesAllBands) ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import \"\(eq.name)\"?").font(.headline)
            EQCurve(bands: eq.eqBands, usesPrecut: eq.preventClipping).frame(height: 120)
            Text("This replaces the current Custom EQ. The iPod changes when you flash it.")
                .foregroundStyle(.secondary)
            if askAllBands {
                Label(CustomEQ.allBandsWarning, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(StatusLabelStyle(tint: .orange))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.pendingEQ = nil }
                    .keyboardShortcut(.cancelAction)
                Button(askAllBands ? "I Agree, Import" : "Import") { model.applyEQ(eq) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

/// One slider of the Simple view.
private struct EQSimpleRow: View {
    let name: String
    @Binding var gain: Int

    var body: some View {
        HStack {
            Text(name).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { Double(gain) / 10 }, set: { gain = Int(($0 * 10).rounded()) }), in: -12...12, step: 0.5) {
                Text(name)
            }
            .labelsHidden()
            Text(String(format: "%+.1f dB", Double(gain) / 10))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
    }
}

/// One band: the type, the frequency, the gain and Q.
private struct EQBandRow: View {
    let number: Int
    @Binding var band: CustomEQ.Band

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Band \(number)").frame(width: 56, alignment: .leading)
                Picker("Type", selection: $band.kind) {
                    ForEach(CustomEQ.Kind.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                TextField("Frequency", value: frequency, format: .number.grouping(.never))
                    .frame(width: 64)
                    .labelsHidden()
                Text("Hz").foregroundStyle(.secondary)
                TextField("Q", value: quality, format: .number.precision(.fractionLength(2)))
                    .frame(width: 48)
                    .labelsHidden()
                Text("Q").foregroundStyle(.secondary)
            }
            HStack {
                Slider(value: gain, in: -12...12, step: 0.5) { Text("Gain") }
                    .labelsHidden()
                Text(String(format: "%+.1f dB", Double(band.gain) / 10))
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }

    private var gain: Binding<Double> {
        Binding(get: { Double(band.gain) / 10 }, set: { band.gain = Int(($0 * 10).rounded()) })
    }

    private var frequency: Binding<Int> {
        Binding(get: { band.frequency }, set: {
            band.frequency = min(max($0, CustomEQ.frequencyRange.lowerBound), CustomEQ.frequencyRange.upperBound)
        })
    }

    private var quality: Binding<Double> {
        Binding(get: { Double(band.q) / 100 }, set: {
            band.q = min(max(Int(($0 * 100).rounded()), CustomEQ.qRange.lowerBound), CustomEQ.qRange.upperBound)
        })
    }
}

/// The curve of the active bands at 44.1 kHz, with the level change if it is on. The range is ±18 dB.
struct EQCurve: View {
    let bands: [CustomEQ.Band]
    let usesPrecut: Bool

    var body: some View {
        Canvas { context, size in
            let range = 18.0
            func y(_ db: Double) -> CGFloat { size.height * (0.5 - db / (2 * range)) }
            var axis = Path()
            axis.move(to: CGPoint(x: 0, y: y(0)))
            axis.addLine(to: CGPoint(x: size.width, y: y(0)))
            context.stroke(axis, with: .color(.secondary.opacity(0.5)))

            let rate = CustomEQ.rates[0]
            let filters = bands.filter { $0.gain != 0 }.map { CustomEQ.biquad($0, rate: rate) }
            let cut = usesPrecut ? CustomEQ.precut(bands, rate: rate) : 0
            var curve = Path()
            for x in stride(from: 0, through: Int(size.width), by: 2) {
                let f = 20 * pow(1000, Double(x) / Double(size.width))
                let db = min(max(CustomEQ.response(filters, frequency: f, rate: rate) + cut, -range), range)
                let p = CGPoint(x: CGFloat(x), y: y(db))
                if x == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
            }
            context.stroke(curve, with: .color(.accentColor), lineWidth: 2)
        }
        .accessibilityLabel("EQ curve")
    }
}
