import Foundation

// What you type has to be a place. There is no search here, so this either
// hands back a URL or hands back nothing — and nothing is worth saying out
// loud, because the alternative is a browser that silently does something else
// with your keystrokes.
enum Address {
    /// Schemes the window can show itself. Anything else typed with a scheme —
    /// mailto:, a custom app link — is somebody else's job and gets refused
    /// here rather than opening a blank tab.
    private static let ours: Set<String> = ["http", "https", "file", "about", "data"]

    static func url(from typed: String) -> URL? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        // Written with a scheme, it is taken at its word.
        if let split = text.range(of: "://") {
            let scheme = text[..<split.lowerBound].lowercased()
            guard ours.contains(scheme) else { return nil }
            return URL(string: text)
        }
        if text.lowercased().hasPrefix("about:") || text.lowercased().hasPrefix("data:") {
            return URL(string: text)
        }

        // Everything else has to look like a host before it gets a scheme put
        // in front of it. "hello world" is not a website, and neither is "todo".
        let head = text.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        guard !head.contains("@") else { return nil }   // an email address
        let host = head.split(separator: ":").first.map(String.init) ?? String(head)
        guard looksLikeHost(host) else { return nil }

        // A local server almost never has a certificate, so https there is a
        // connection failure rather than a page.
        return URL(string: (Dialogs.isLocal(host) ? "http://" : "https://") + text)
    }

    private static func looksLikeHost(_ host: String) -> Bool {
        if host == "localhost" { return true }

        // Four numbers is an address on the local network as often as not.
        let numbers = host.split(separator: ".", omittingEmptySubsequences: false)
        if numbers.count == 4, numbers.allSatisfy({ UInt8($0) != nil }) { return true }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        guard labels.allSatisfy({ label in
            !label.isEmpty
                && !label.hasPrefix("-")
                && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }) else { return false }

        // The last label carries the weight: a dotted thing ending in letters is
        // a domain, a dotted thing ending in digits is a version number.
        let tld = labels[labels.count - 1]
        return tld.count >= 2 && tld.allSatisfy { $0.isLetter }
    }

    /// What the tab says before the page has told us its title: the address,
    /// with the parts nobody reads taken off.
    static func pretty(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path()
        return path.isEmpty || path == "/" ? bare : bare + path
    }
}
