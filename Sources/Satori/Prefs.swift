import SwiftUI

// Everything there is to set, in one observable place.
//
// Each of these is a line in the settings file and nothing more; the object
// exists so that a panel can bind to them and the rest of the window can
// redraw when one changes. Defaults are chosen so that a browser nobody has
// configured behaves the way it always did.

/// What a tab wears beside its title, and what a pinned one is reduced to: a
/// letter, or the site's own icon.
enum Glyph: String, CaseIterable, Identifiable {
    case letters, icons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .letters: return "Letters"
        case .icons: return "Site icons"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    private let store = Store.settings

    /// A local socket a script can drive the browser through, in tabs of its
    /// own. Off unless asked for.
    @Published var bench: Bool {
        didSet { store.set(bench, forKey: "bench") }
    }
    /// Dark, light, or the Mac's own.
    @Published var look: Look {
        didSet {
            store.set(look.rawValue, forKey: "look")
            look.apply()
        }
    }
    /// Whether the top bar takes the colour of the page. On unless turned off.
    @Published var adaptive: Bool {
        didSet { store.set(adaptive, forKey: "adaptive") }
    }
    /// Titles down the left instead of across the top.
    @Published var sidebar: Bool {
        didSet { store.set(sidebar, forKey: "sidebar") }
    }
    /// How wide the column is. Pulled by its edge, and remembered.
    @Published var sideWidth: CGFloat {
        didSet { store.set(Double(sideWidth), forKey: "sidebar.width") }
    }
    @Published var glyph: Glyph {
        didSet { store.set(glyph.rawValue, forKey: "glyph") }
    }
    /// Tabs nobody has looked at for half an hour give their page back and
    /// keep where they were. On unless turned off.
    @Published var sleepsTabs: Bool {
        didSet { store.set(sleepsTabs, forKey: "tabs.sleep") }
    }
    /// A video playing in a tab you step away from goes on in the little
    /// window. On unless turned off; ⌘⇧P still lifts one by hand.
    @Published var floatsVideo: Bool {
        didSet { store.set(floatsVideo, forKey: "float.auto") }
    }
    /// The ad blocker. On unless turned off; there is nothing else to it.
    @Published var shielded: Bool {
        didSet { store.set(shielded, forKey: "shield") }
    }
    @Published var downloads: URL {
        didSet { store.set(downloads.path, forKey: "downloads") }
    }
    @Published var asksWhereToSave: Bool {
        didSet { store.set(asksWhereToSave, forKey: "downloads.ask") }
    }
    /// Check for updates on its own, every day. Off means only when asked,
    /// through the button below it. Takes effect without a restart.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            store.set(automaticallyChecksForUpdates, forKey: UpdaterController.automaticChecksKey)
            // A web app never boots Sparkle in the first place (see
            // SatoriApp.init) — asking it to change a setting it doesn't
            // have would instantiate it just to do that.
            if !WebApp.on { UpdaterController.shared.setAutomaticallyChecksForUpdates(automaticallyChecksForUpdates) }
        }
    }
    /// Offer to keep a password the first time a site sees it.
    @Published var savesPasswords: Bool {
        didSet { store.set(savesPasswords, forKey: "passwords.save") }
    }
    /// Put a kept name and password into a sign-in as soon as one appears.
    @Published var fillsPasswords: Bool {
        didSet { store.set(fillsPasswords, forKey: "passwords.fill") }
    }
    /// The first launch has been walked through. Until then the welcome
    /// stands over the window.
    @Published var welcomed: Bool {
        didSet { store.set(welcomed, forKey: "welcomed") }
    }
    /// macOS's own autocorrect, inside web pages: the little "Not ×" that
    /// capitalises what you meant to leave lower-case. Off unless asked for.
    @Published var autocorrect: Bool {
        didSet {
            store.set(autocorrect, forKey: "autocorrect")
            Preferences.tellWebKit(autocorrect: autocorrect)
        }
    }
    /// Words that aren't a place go here. DuckDuckGo unless asked otherwise.
    @Published var engine: Engine {
        didSet { store.set(engine.rawValue, forKey: "engine") }
    }
    /// Combos the person taught, by action name. Empty means every default —
    /// never read directly, `binding(for:)` falls back to the preset.
    @Published var shortcutOverrides: [String: String] {
        didSet { store.set(shortcutOverrides, forKey: "shortcuts") }
    }
    /// The action being taught a combo right now, if any. While set, the
    /// app's own key monitor stands down so teaching never triggers.
    @Published var recording: ShortcutAction? = nil

    init() {
        // Carried over from when there were four ways of holding the browser
        // and this was one of them.
        // Light unless asked otherwise — the browser was only ever light
        // before this was a choice.
        bench = store.bool(forKey: "bench")
        let chosen = store.string(forKey: "look").flatMap(Look.init) ?? .light
        look = chosen
        adaptive = store.object(forKey: "adaptive") as? Bool ?? true
        // Before the first window, and not deferred: the window that is about
        // to be made should be made in the right appearance.
        NSApp.appearance = chosen.appearance
        sidebar = store.object(forKey: "sidebar") as? Bool
            ?? (store.string(forKey: "manner") == "side")
        let width = store.object(forKey: "sidebar.width") as? Double ?? Double(Metrics.side)
        sideWidth = min(Metrics.sideMax, max(Metrics.sideMin, CGFloat(width)))
        glyph = store.string(forKey: "glyph").flatMap(Glyph.init) ?? .icons
        sleepsTabs = store.object(forKey: "tabs.sleep") as? Bool ?? true
        floatsVideo = store.object(forKey: "float.auto") as? Bool ?? true
        shielded = store.object(forKey: "shield") as? Bool ?? true
        // A test run downloads into its own folder: ~/Downloads would have
        // macOS stop it to ask for access, with a dialog on the screen of
        // whoever is working beside it.
        let testDownloads = Store.folder.appendingPathComponent("Downloads", isDirectory: true)
        if Store.testing { try? FileManager.default.createDirectory(at: testDownloads, withIntermediateDirectories: true) }
        downloads = Store.testing
            ? testDownloads
            : (store.string(forKey: "downloads")).map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        asksWhereToSave = store.object(forKey: "downloads.ask") as? Bool ?? true
        automaticallyChecksForUpdates = store.object(forKey: UpdaterController.automaticChecksKey) as? Bool ?? true
        savesPasswords = store.object(forKey: "passwords.save") as? Bool ?? true
        fillsPasswords = store.object(forKey: "passwords.fill") as? Bool ?? true
        // Anyone who already has a session was here before the welcome
        // existed; they are not asked to sit through it.
        welcomed = store.bool(forKey: "welcomed") || store.object(forKey: "glyph") != nil
        let corrects = store.bool(forKey: "autocorrect")
        autocorrect = corrects
        // Before the first web view exists: WebKit reads these once.
        Preferences.tellWebKit(autocorrect: corrects)
        engine = Engine(rawValue: store.string(forKey: "engine") ?? "") ?? .duckduckgo
        shortcutOverrides = store.dictionary(forKey: "shortcuts") as? [String: String] ?? [:]
    }

    /// WebKit's text checker takes its orders from the app's standard
    /// defaults — the real ones, not the test suite, because it is WebKit
    /// reading them and not us. Smart quotes and dashes go off outright: in a
    /// browser they are wrong in every code field and wanted in almost none.
    static func tellWebKit(autocorrect: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(autocorrect, forKey: "WebAutomaticSpellingCorrectionEnabled")
        defaults.set(false, forKey: "WebAutomaticQuoteSubstitutionEnabled")
        defaults.set(false, forKey: "WebAutomaticDashSubstitutionEnabled")
    }
}
