import IPodFWKit
import SwiftUI

/// The editor of the patch custom-eq in the Patches pane. The build calculates the filters from the
/// bands (`Patcher.setOptions`). To change the iPod, flash it again.
struct CustomEQView: View {
    @EnvironmentObject var model: AppModel
    let patch: PatchInfo

    var body: some View {
        let bands = model.eqBands(patch)
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
                ForEach(bands.indices, id: \.self) { i in
                    EQBandRow(number: i + 1, band: Binding(get: { bands[i] }, set: { b in
                        var all = bands
                        all[i] = b
                        model.setEQBands(patch, all)
                    }))
                }
            } else {
                ForEach(bands.indices, id: \.self) { i in
                    EQSimpleRow(name: CustomEQ.simpleNames[i], gain: Binding(get: { bands[i].gain }, set: { g in
                        var all = CustomEQ.simple(from: bands)
                        all[i].gain = g
                        model.setEQBands(patch, all)
                    }))
                }
            }
            Toggle("Prevent Clipping", isOn: Binding(get: { usesPrecut }, set: { model.setEQUsesPrecut(patch, $0) }))
            let cut = CustomEQ.precut(bands)
            if usesPrecut, cut < -0.05 {
                LabeledContent("Level", value: String(format: "%.1f dB", cut))
            }
            Button("Reset Bands") { model.setEQBands(patch, advanced ? CustomEQ.defaults : CustomEQ.simpleLayout) }
                .disabled(advanced ? bands == CustomEQ.defaults : bands.allSatisfy { $0.gain == 0 })
        } header: {
            Text("Custom EQ")
        } footer: {
            Text("A band at 0 dB is off. Simple keeps only the slider values of Advanced bands. Prevent Clipping lowers the level by the highest boost, so that loud music does not distort. The music then sounds quieter than Flat. Without it, the EQ operates as the Apple presets do, and a strong boost can distort.")
        }
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
private struct EQCurve: View {
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
