import Foundation

// What to do with words that aren't a place: ask the chosen engine.
//
// The field still tells an address from a phrase — typing a domain goes
// straight there, without a round trip through anyone's results page. Only
// what can't be a place gets searched.

enum Engine: String, CaseIterable, Identifiable {
    case google, duckduckgo, brave, bing, kagi, ecosia, startpage, yahoo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .brave: return "Brave Search"
        case .bing: return "Bing"
        case .kagi: return "Kagi"
        case .ecosia: return "Ecosia"
        case .startpage: return "Startpage"
        case .yahoo: return "Yahoo"
        }
    }

    /// The engine answering now, for the field and the suggestions alike.
    /// Google unless asked otherwise.
    static var current: Engine {
        Engine(rawValue: Store.settings.string(forKey: "engine") ?? "") ?? .google
    }

    /// A place if it can be one, a search if it can't.
    static func destination(for typed: String) -> URL? {
        Address.url(from: typed) ?? url(for: typed)
    }

    static func url(for text: String) -> URL? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        // Everything a query string can't carry raw, including the plus sign,
        // which would otherwise come out the far end as a space.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let escaped = words.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        return URL(string: current.query + escaped)
    }

    private var query: String {
        switch self {
        case .google: return "https://www.google.com/search?q="
        case .duckduckgo: return "https://duckduckgo.com/?q="
        case .brave: return "https://search.brave.com/search?q="
        case .bing: return "https://www.bing.com/search?q="
        case .kagi: return "https://kagi.com/search?q="
        case .ecosia: return "https://www.ecosia.org/search?q="
        case .startpage: return "https://www.startpage.com/sp/search?query="
        case .yahoo: return "https://search.yahoo.com/search?p="
        }
    }
}
