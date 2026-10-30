import AppKit
import IPodFWKit
import SwiftUI

struct EmulatorView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var emu: EmulatorManager
    @EnvironmentObject var session: EmulatorSession
    @AppStorage("emulatorLibrary") var library = "test"
    @AppStorage("emulatorMusicFolder") var musicFolder = ""
    @AppStorage("emulatorSongCount") var songCount = 200

    var body: some View {
        HSplitView {
            PreviewPanel()
                .frame(minWidth: 400, idealWidth: 460, maxWidth: .infinity)
            Form {
                Section {
                    HStack {
                        Button(session.isActive ? "Restart with Latest Edits" : "Run in Emulator") {
                            model.runInEmulator(emu, session)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.editor == nil || !emu.toolsReady || (library == "folder" && musicFolder.isEmpty))
                        Button("Stop") { session.stop() }.disabled(!session.isActive)
                    }
                    if model.editor == nil { Text("Open a firmware first.").foregroundStyle(.secondary) }
                    Picker("Music on the test iPod", selection: $library) {
                        Text("None").tag("none")
                        Text("Test library (60 songs, 6 albums)").tag("test")
                        Text("Songs from a folder").tag("folder")
                    }
                    if library == "folder" {
                        HStack {
                            Text(musicFolder.isEmpty ? "No folder chosen" : (musicFolder as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(musicFolder.isEmpty ? .secondary : .primary)
                            Spacer()
                            Button("Choose…") {
                                let p = NSOpenPanel()
                                p.canChooseDirectories = true
                                p.canChooseFiles = false
                                p.message = "Choose a folder of .m4a music files. The files are only read."
                                if p.runModal() == .OK, let url = p.url { musicFolder = url.path }
                            }
                        }
                        Stepper("Songs: \(songCount) (maximum 8 from each album; the audio is copied)", value: $songCount, in: 20...1000, step: 20)
                    }
                    if model.enabledPatches.isEmpty == false {
                        Label("Patches included: \(model.activePatches.map(\.spec.name).joined(separator: ", "))", systemImage: "puzzlepiece.extension")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.appearance != .light, let t = model.selectedTheme {
                        Label(model.appearance == .dark ? "Dark theme included: \(t.name)" : "Dark Mode item in Settings: \(t.name)", systemImage: "moon.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("iPodFirm makes a drive from your current changes and starts it from cold in this pane. The test iPod is separate, thus your own emulator devices do not change. Run it again after each change.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Test iPod in the Emulator Window") {
                        Task {
                            session.stop()
                            do {
                                if emu.lastRun == nil { throw FirmwareError("Click Run in Emulator first. This makes the test drive.") }
                                try await emu.openWindow()
                            } catch { model.fail("Cannot Open the Emulator", error) }
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
                            Label("ipod-emulator \(v)", systemImage: "checkmark.circle.fill").labelStyle(StatusLabelStyle(tint: .green))
                        } else {
                            Label("The emulator is not installed", systemImage: "exclamationmark.circle").labelStyle(StatusLabelStyle(tint: .orange))
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
                    FormFooter("Built from siggifly/ipod-emulator's source (Rust is installed into your home folder if needed). No sound or USB.")
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
        }
        .onAppear { emu.refresh() }
    }
}

struct PreviewPanel: View {
    @EnvironmentObject var session: EmulatorSession
    @FocusState private var focused: Bool

    /// The size of the iPod body. The body does not stretch with the window.
    static let bodySize = CGSize(width: 370, height: 620)

    var body: some View {
        GeometryReader { geo in
            // A tall column shows the iPod larger, to a maximum of 1.4 times.
            let scale = min(1.4, max(1, min((geo.size.width - 40) / Self.bodySize.width, (geo.size.height - 40) / Self.bodySize.height)))
            device
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .contentShape(Rectangle())
        .focusable()
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

    /// The iPod: the screen and the click wheel on the body.
    var device: some View {
        VStack(spacing: 44) {
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
        .padding(.top, 34)
        .frame(width: Self.bodySize.width, height: Self.bodySize.height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.gray.opacity(0.3)))
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
            label(Text("MENU"), "Menu", .menu).offset(y: -size * 0.37)
            label(Image(systemName: "backward.end.alt.fill"), "Previous", .prev).offset(x: -size * 0.37)
            label(Image(systemName: "forward.end.alt.fill"), "Next", .next).offset(x: size * 0.37)
            label(Image(systemName: "playpause.fill"), "Play/Pause", .play).offset(y: size * 0.37)
            Button { session.press(.select) } label: {
                Circle().fill(Color(white: 0.93)).overlay(Circle().stroke(Color.gray.opacity(0.35)))
                    .frame(width: size * 0.36, height: size * 0.36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select")
        }
        .frame(width: size, height: size)
    }

    func label(_ content: some View, _ name: String, _ b: EmulatorSession.Button) -> some View {
        Button { session.press(b) } label: {
            content.font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.55))
                .frame(width: 44, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
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
