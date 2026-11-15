import AppKit
import IPodFWKit
import UniformTypeIdentifiers

/// Custom fonts: the app keeps them in Application Support/iPodFirm/Fonts, one file for each font
/// that is not the Apple font. Each build puts them into rsrc (IPodFonts). Research: re/fonts.md.
extension AppModel {
    /// The question before a flash that would replace fonts on the iPod that are not Apple fonts.
    struct FontQuestion: Identifiable {
        let id = UUID()
        let plan: FlashPlan
        /// The custom fonts of the iPod that the flash would replace.
        let fonts: [String: [UInt8]]
    }

    nonisolated static let fontsDir = supportDir.appendingPathComponent("Fonts")

    /// The custom fonts of the app, by name. Only the 8 names of IPodFonts count.
    nonisolated static func loadCustomFonts() -> [String: [UInt8]] {
        var out: [String: [UInt8]] = [:]
        for name in IPodFonts.names {
            if let data = try? Data(contentsOf: fontsDir.appendingPathComponent(name)) { out[name] = [UInt8](data) }
        }
        return out
    }

    nonisolated static func customFontSizes() -> [String: Int] { loadCustomFonts().mapValues(\.count) }

    /// Apple's firmware 1.3 and its fonts.
    struct AppleFonts {
        let ipsw: URL
        let fonts: [String: [UInt8]]
    }

    func appleFonts() async throws -> AppleFonts {
        let ipsw = try await ensureAppleIPSW()
        let fonts = try await Task.detached { try IPodFonts.fonts(in: FirmwarePartition(data: IPSW.extractFirmware(ipsw).data)) }.value
        return AppleFonts(ipsw: ipsw, fonts: fonts)
    }

    /// Checks `fonts` and keeps the ones that are not Apple fonts. Together with the fonts that the app
    /// already has, they must fit in rsrc. Returns the names of the fonts that the app keeps.
    @discardableResult
    func saveFonts(_ fonts: [String: [UInt8]], apple base: AppleFonts) throws -> [String] {
        AppLog.debug("Fonts: save \(fonts.count) font(s) in the app")
        let apple = base.fonts
        let custom = IPodFonts.custom(fonts, apple: apple)
        for (name, data) in custom { try IPodFonts.check(name, data, apple: apple) }
        var all = Self.loadCustomFonts()
        for name in fonts.keys { all[name] = nil }
        all.merge(custom) { $1 }
        // the same build as a flash: all the custom fonts in the Apple rsrc
        let trial = try FirmwarePartition(data: IPSW.extractFirmware(base.ipsw).data)
        try IPodFonts.apply(all, to: trial)
        try FileManager.default.createDirectory(at: Self.fontsDir, withIntermediateDirectories: true)
        for name in fonts.keys where custom[name] == nil {
            // the Apple font: the app needs no file for it
            let url = Self.fontsDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        for (name, data) in custom { try Data(data).write(to: Self.fontsDir.appendingPathComponent(name), options: .atomic) }
        customFontSizes = Self.customFontSizes()
        return custom.keys.sorted()
    }

    /// Import the fonts from an iPodFirm backup, a firmware file, an .ipsw or .ttf files.
    func importFontsFromFile() {
        AppLog.debug("Action: import the fonts from a file")
        let panel = NSOpenPanel()
        panel.message = "Select a backup, a firmware file or font files from iPodWizard."
        panel.allowedContentTypes = ["bin", "ipsw", "ttf"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task {
            do {
                let apple = try await appleFonts()
                var fonts: [String: [UInt8]] = [:]
                for url in urls {
                    switch url.pathExtension.lowercased() {
                    case "ttf":
                        guard IPodFonts.names.contains(url.lastPathComponent) else {
                            throw FirmwareError("The file \(url.lastPathComponent) does not have the name of an iPod font. "
                                                + "Give it one of these names: \(IPodFonts.names.joined(separator: ", ")).")
                        }
                        fonts[url.lastPathComponent] = [UInt8](try Data(contentsOf: url))
                    case "ipsw":
                        fonts.merge(IPodFonts.custom(try IPodFonts.fonts(in: FirmwarePartition(data: IPSW.extractFirmware(url).data)), apple: apple.fonts)) { $1 }
                    default:
                        let data = [UInt8](try Data(contentsOf: url))
                        fonts.merge(IPodFonts.custom(try IPodFonts.fonts(in: FirmwarePartition(data: data)), apple: apple.fonts)) { $1 }
                    }
                }
                let kept = try saveFonts(fonts, apple: apple)
                alert = kept.isEmpty
                    ? AlertInfo(title: "No Custom Fonts", message: "The files have only the Apple fonts.")
                    : AlertInfo(title: "Fonts Imported", message: "iPodFirm uses these fonts at the next flash: \(kept.joined(separator: ", ")).")
            } catch { fail("Cannot Import the Fonts", error) }
        }
    }

    /// Import the fonts that are on the iPod now, for example fonts from iPodWizard.
    func importFontsFromIPod() async {
        AppLog.debug("Action: import the fonts from the iPod")
        guard busy == nil else { return }
        guard let ipod = currentIPod else {
            alert = AlertInfo(title: "No iPod Is Connected", message: "Connect the iPod. Then try again.")
            return
        }
        do {
            let apple = try await appleFonts()
            busy = "Reading the fonts of the iPod…"
            defer { busy = nil }
            let fonts = try await Task.detached { try Operations.readFonts(ipod, access: .authOpen()) }.value
            let kept = try saveFonts(IPodFonts.custom(fonts, apple: apple.fonts), apple: apple)
            alert = kept.isEmpty
                ? AlertInfo(title: "No Custom Fonts", message: "The iPod has only the Apple fonts.")
                : AlertInfo(title: "Fonts Imported", message: "iPodFirm uses these fonts at the next flash: \(kept.joined(separator: ", ")).")
        } catch { fail("Cannot Read the Fonts", error) }
    }

    /// Remove the custom fonts of the app. The next flash writes the Apple fonts.
    func useAppleFonts() {
        AppLog.debug("Action: use the Apple fonts")
        for name in IPodFonts.names {
            let url = Self.fontsDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
        }
        customFontSizes = Self.customFontSizes()
    }

    /// The dry run of a flash found custom fonts on the iPod that the flash would replace. Ask first.
    /// Returns true if the app asks.
    func askAboutIPodFonts(_ plan: FlashPlan) async -> Bool {
        guard plan.reason == "flash", let onIPod = plan.result.fontsOnIPod, !onIPod.isEmpty else { return false }
        // Without the Apple fonts, the app cannot tell which fonts are custom: then it asks for all.
        let apple = try? await appleFonts()
        let custom = apple.map { IPodFonts.custom(onIPod, apple: $0.fonts) } ?? onIPod
        guard !custom.isEmpty else { return false }
        fontQuestion = FontQuestion(plan: plan, fonts: custom)
        return true
    }

    /// Keep the fonts of the iPod: import them, then build the flash image again.
    func keepIPodFonts(_ q: FontQuestion) async {
        AppLog.debug("Action: keep the fonts of the iPod")
        fontQuestion = nil
        do {
            try saveFonts(q.fonts, apple: try await appleFonts())
            await flashEdited()
        } catch { fail("Cannot Keep the Fonts", error) }
    }
}
