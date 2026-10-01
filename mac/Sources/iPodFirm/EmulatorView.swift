import AppKit
import IPodFWKit
import SwiftUI

struct EmulatorView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var emu: EmulatorManager
    @EnvironmentObject var session: EmulatorSession
    @AppStorage("emulatorTestLibrary") var testLibrary = true

    var body: some View {
        HSplitView {
            PreviewPanel()
                .frame(minWidth: 380, idealWidth: 420)
            Form {
                Section {
                    HStack {
                        Button(session.isActive ? "Restart with Latest Edits" : "Run in Emulator") {
                            model.runInEmulator(emu, session)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.editor == nil || !emu.toolsReady)
                        Button("Stop") { session.stop() }.disabled(!session.isActive)
                    }
                    if model.editor == nil { Text("Open a firmware first.").foregroundStyle(.secondary) }
                    Toggle("Include a test music library (60 songs in 6 albums)", isOn: $testLibrary)
                    Text("Builds a drive from your current edits and boots it from cold, right here. It's a separate test iPod — your own emulator devices are left alone. Re-run after every change.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Test iPod in the Emulator Window") {
                        Task {
                            session.stop()
                            do {
                                if emu.lastRun == nil { throw FirmwareError("Run it here first so the test drive is built.") }
                                try await emu.openWindow()
                            } catch { model.fail("Couldn't open the emulator", error) }
                        }
                    }
                    .disabled(emu.installedVersion == nil)
                } header: { Text("Test your firmware") }

                Section {
                    Grid(alignment: .leading, verticalSpacing: 4) {
                        GridRow { Text("Wheel").foregroundStyle(.secondary); Text("drag around the ring, scroll over it, or use ↑ ↓") }
                        GridRow { Text("Select").foregroundStyle(.secondary); Text("centre button or Return") }
                        GridRow { Text("Menu").foregroundStyle(.secondary); Text("MENU or Esc") }
                        GridRow { Text("Play/Pause").foregroundStyle(.secondary); Text("bottom or Space") }
                        GridRow { Text("Prev / Next").foregroundStyle(.secondary); Text("sides or ← →") }
                    }
                    .font(.callout)
                } header: { Text("Controls") }

                Section {
                    HStack {
                        if let v = emu.installedVersion {
                            Label("ipod-emulator \(v)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Label("The emulator isn't installed yet", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        }
                        Spacer()
                        Button(emu.installedVersion == nil ? "Install Emulator" : "Update Emulator") { emu.install() }
                            .disabled(emu.installing || session.isActive)
                    }
                    if emu.installing || !emu.log.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(emu.log).font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                                Color.clear.frame(height: 1).id("end")
                            }
                            .frame(height: 140)
                            .onChange(of: emu.log) { _, _ in proxy.scrollTo("end") }
                        }
                    }
                } header: { Text("Emulator") } footer: {
                    Text("Built from siggifly/ipod-emulator's source (Rust is installed into your home folder if needed). No sound or USB.")
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320)
        }
        .onAppear { emu.refresh() }
    }
}

struct PreviewPanel: View {
    @EnvironmentObject var session: EmulatorSession
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.black)
                if let img = session.screen {
                    Image(nsImage: img).interpolation(.none).resizable().aspectRatio(4 / 3, contentMode: .fit)
                }
                overlay
            }
            .frame(width: 320, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.5)))

            ClickWheel()
                .opacity(session.phase == .running ? 1 : 0.45)
                .disabled(session.phase != .running)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                .padding(12)
        )
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onTapGesture { focused = true }
        .onKeyPress(.upArrow) { session.wheel(-EmulatorSession.detentsPerItem); return .handled }
        .onKeyPress(.downArrow) { session.wheel(EmulatorSession.detentsPerItem); return .handled }
        .onKeyPress(.return) { session.press(.select); return .handled }
        .onKeyPress(.escape) { session.press(.menu); return .handled }
        .onKeyPress(.space) { session.press(.play); return .handled }
        .onKeyPress(.leftArrow) { session.press(.prev); return .handled }
        .onKeyPress(.rightArrow) { session.press(.next); return .handled }
    }

    @ViewBuilder var overlay: some View {
        switch session.phase {
        case .stopped where session.screen == nil:
            Text("Not running").foregroundStyle(.white.opacity(0.6))
        case .preparing:
            VStack(spacing: 8) { ProgressView().controlSize(.small).tint(.white); Text("Building the drive…") }
                .foregroundStyle(.white)
        case .booting(let f) where session.screen == nil || f < 0.15:
            VStack(spacing: 8) {
                ProgressView(value: f).frame(width: 160).tint(.white)
                Text("Booting from cold…")
            }
            .foregroundStyle(.white)
        case .failed(let msg):
            Text(msg).foregroundStyle(.white).multilineTextAlignment(.center).padding()
        default:
            EmptyView()
        }
    }
}

struct ClickWheel: View {
    @EnvironmentObject var session: EmulatorSession
    @State private var lastAngle: Double?
    @State private var accumulated: Double = 0
    let size: CGFloat = 210
    let degreesPerDetent: Double = 4

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
                .overlay(Circle().stroke(Color.gray.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                .gesture(ringDrag)
                .overlay(ScrollCatcher { dy in rotate(by: dy * 2) })
            label("MENU", .menu).offset(y: -size * 0.37)
            label("⏮", .prev).offset(x: -size * 0.37)
            label("⏭", .next).offset(x: size * 0.37)
            label("⏯", .play).offset(y: size * 0.37)
            Button { session.press(.select) } label: {
                Circle().fill(Color(white: 0.93)).overlay(Circle().stroke(Color.gray.opacity(0.35)))
                    .frame(width: size * 0.36, height: size * 0.36)
            }
            .buttonStyle(.plain)
        }
        .frame(width: size, height: size)
    }

    func label(_ text: String, _ b: EmulatorSession.Button) -> some View {
        Button { session.press(b) } label: {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.55))
                .frame(width: 44, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var ringDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                let c = CGPoint(x: size / 2, y: size / 2)
                let a = atan2(v.location.y - c.y, v.location.x - c.x) * 180 / .pi
                if let last = lastAngle {
                    var d = a - last
                    if d > 180 { d -= 360 }
                    if d < -180 { d += 360 }
                    rotate(by: d)
                }
                lastAngle = a
            }
            .onEnded { _ in lastAngle = nil; accumulated = 0 }
    }

    /// Clockwise is positive (down the list), like the real wheel.
    func rotate(by degrees: Double) {
        accumulated += degrees
        let detents = Int(accumulated / degreesPerDetent)
        if detents != 0 {
            session.wheel(detents)
            accumulated -= Double(detents) * degreesPerDetent
        }
    }
}

/// Trackpad / mouse-wheel scrolling over the click wheel.
struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (Double) -> Void

    final class CatcherView: NSView {
        var onScroll: ((Double) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
            onScroll?(-dy)
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            // only claim scroll events; let clicks and drags reach SwiftUI
            NSApp.currentEvent?.type == .scrollWheel ? self : nil
        }
    }

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) { v.onScroll = onScroll }
}
