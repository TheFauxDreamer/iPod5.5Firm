import Foundation

/// Gets the number of the newest iPodFirm release from GitHub. The app does not download the
/// update. It only tells the user and opens the release page in the browser.
public enum UpdateCheck {
    /// One release on GitHub.
    public struct Release: Equatable, Sendable {
        /// The version without the "v" of the tag, for example "0.1.180".
        public let version: String
        /// The release page on GitHub.
        public let url: URL

        public init(version: String, url: URL) {
            self.version = version
            self.url = url
        }
    }

    /// GitHub gives the newest release that is not a draft and not a pre-release.
    public static let latestURL = URL(string: "https://api.github.com/repos/TheFauxDreamer/iPod5.5Firm/releases/latest")!

    private struct Reply: Decodable {
        let tag_name: String
        let html_url: URL
    }

    /// Decodes the JSON reply of `latestURL`.
    public static func parse(_ data: Data) throws -> Release {
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        var version = reply.tag_name
        if version.hasPrefix("v") || version.hasPrefix("V") { version.removeFirst() }
        return Release(version: version, url: reply.html_url)
    }

    /// The numbers of a version, or nil if a part is not a number (for example "dev").
    static func numbers(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.map { $0! }
    }

    /// True if `remote` is a higher version than `local`. A missing number counts as 0, thus
    /// "0.2" is equal to "0.2.0". A version that is not a number gives false.
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        guard let r = numbers(remote), let l = numbers(local) else { return false }
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Asks GitHub for the newest release. The request sends no data about the user or the iPod.
    public static func fetchLatest() async throws -> Release {
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FirmwareError("GitHub gave the HTTP status \(http.statusCode).")
        }
        return try parse(data)
    }
}
