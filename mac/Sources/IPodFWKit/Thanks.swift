import Foundation

/// One person or project on the Thanks sheet.
public struct ThanksEntry: Identifiable, Sendable {
    public let name: String
    public let reason: String
    public let link: URL?
    /// The first app version with the fix or the idea, for example "0.1.172". nil: the item was in the
    /// app from the start.
    public let version: String?
    public var id: String { name }

    public init(name: String, reason: String, link: URL? = nil, version: String? = nil) {
        self.name = name
        self.reason = reason
        self.link = link
        self.version = version
    }

    /// The numbers of `version`, for a numeric sort ("0.1.10" comes after "0.1.9").
    public var versionNumbers: [Int] { version?.split(separator: ".").compactMap { Int($0) } ?? [] }
}

/// The people that Help > Thanks… shows.
public enum Thanks {
    /// To thank a person for a bug report or a fix, add an entry here with the first app version
    /// that has the fix. The order in this list is not important: `sorted` puts the newest version
    /// first. Also add the person to the Credits section of README.md.
    public static let people: [ThanksEntry] = [
        ThanksEntry(name: "Matthew98", reason: "The \"5.5G Ultimate Background Hack\" theme. The dark theme starts from it."),
        ThanksEntry(name: "braniak87", reason: "Found the cause of the crash when the Patches pane opened, gave the fix and tested it (GitHub issue 1).",
                    link: URL(string: "https://github.com/TheFauxDreamer/iPod5.5Firm/issues/1"), version: "0.1.172"),
        ThanksEntry(name: "Milli5410", reason: "The dark mode of the dark theme."),
        ThanksEntry(name: "rockpod (nuxcodes)", reason: "The idea of SSD Mode.",
                    link: URL(string: "https://github.com/nuxcodes/rockpod")),
        ThanksEntry(name: "osos-lab (RepriseOS)", reason: "The idea of the Album Artists menu."),
        ThanksEntry(name: "iPodWizard", reason: "The file formats of the firmware pictures and text.",
                    link: URL(string: "https://sourceforge.net/projects/ipodwizard/")),
        ThanksEntry(name: "Rockbox ipodpatcher", reason: "The file formats of the iPod disk and the firmware partition.",
                    link: URL(string: "https://github.com/Rockbox/rockbox/tree/master/utils/ipodpatcher")),
        ThanksEntry(name: "siggifly/ipod-emulator", reason: "The emulator that the Emulator pane uses.",
                    link: URL(string: "https://github.com/siggifly/ipod-emulator")),
    ]

    /// `people` with the newest version first. The entries with no version come last, in the list order.
    public static var sorted: [ThanksEntry] { sorted(people) }

    /// Sorts `entries`: the newest version first, then the entries with no version in the list order.
    public static func sorted(_ entries: [ThanksEntry]) -> [ThanksEntry] {
        entries.enumerated().sorted { a, b in
            let x = a.element.versionNumbers, y = b.element.versionNumbers
            if x != y { return y.lexicographicallyPrecedes(x) }
            return a.offset < b.offset
        }.map(\.element)
    }
}
