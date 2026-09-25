import SwiftUI

/// Everything there is to set. Pages down the left, one page at a time on
/// the right, each a short list of lines with a hairline between them —
/// nothing to scroll through, nothing to hunt for. The same white and
/// hairline as the rest of the app; the same pill for the page you are on
/// as for the tab you are on.
struct SettingsPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @ObservedObject private var shield = Shield.shared
    @State private var isDefault = Links.isDefault
    @State private var page: Page = Page(rawValue: Store.settings.string(forKey: "settings.page") ?? "")
        .flatMap { SettingsPanel.shown.contains($0) ? $0 : nil } ?? .general
    @StateObject private var recorder = ShortcutRecorder()

    enum Page: String, CaseIterable, Identifiable {
        case general, tabs, search, extensions, passwords, shortcuts, privacy, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "General"
            case .tabs: return "Tabs"
            case .search: return "Search"
            case .extensions: return "Extensions"
            case .passwords: return "Passwords"
            case .shortcuts: return "Shortcuts"
            case .privacy: return "Privacy"
            case .about: return "About"
            }
        }
        var icon: String {
            switch self {
            case .general: return "macwindow"
            case .tabs: return "rectangle.split.3x1"
            case .search: return "magnifyingglass"
            case .extensions: return "puzzlepiece.extension"
            case .passwords: return "key"
            case .shortcuts: return "keyboard"
            case .privacy: return "hand.raised"
            case .about: return "info.circle"
            }
        }
    }

    /// The pages there are. Extensions are hidden for the first public
    /// release. A web app is one site in one window: no tabs to arrange, no
    /// address bar to search from, no extensions, the browser's shortcuts
    /// are the browser's, and passwords are the browser's keychain's.
    static var shown: [Page] {
        Page.allCases.filter { page in
            if EXTENSIONS_HIDDEN, page == .extensions { return false }
            if WebApp.on, [.tabs, .search, .extensions, .shortcuts, .passwords].contains(page) { return false }
            return true
        }
    }

    private static let rail: CGFloat = 168
    private static let width: CGFloat = 660
    private static let height: CGFloat = 500

    var body: some View {
        HStack(spacing: 0) {
            pages
            Rectangle().fill(Palette.hairline).frame(width: 1)
            content
        }
        .frame(width: SettingsPanel.width, height: SettingsPanel.height)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 34, y: 12)
        .onChange(of: page) { _, page in Store.settings.set(page.rawValue, forKey: "settings.page") }
    }

    // MARK: - the rail

    private var pages: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)
            ForEach(SettingsPanel.shown) { item in
                PageRow(page: item, on: page == item) { page = item }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: SettingsPanel.rail, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.wash.opacity(0.45))
    }

    private struct PageRow: View {
        let page: Page
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                HStack(spacing: 9) {
                    Image(systemName: page.icon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16)
                    Text(page.title)
                        .font(.system(size: 13, weight: on ? .medium : .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.75) : Palette.muted))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? Palette.ground : (hovering ? Palette.hover : .clear))
                        .shadow(color: .black.opacity(on ? 0.06 : 0), radius: 3, y: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }

    // MARK: - the page

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(page.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Door(icon: "xmark", help: "Done   esc") { browser.tuning = false }
            }
            .padding(.bottom, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .general: general
                    case .tabs: tabs
                    case .search: search
                    case .extensions: ExtensionsPage(browser: browser)
                    case .passwords: passwords
                    case .shortcuts: shortcuts
                    case .privacy: privacy
                    case .about: about
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - general

    private var general: some View {
        Card {
            // A web app is one site under its own name — offering to make it
            // the Mac's default browser would hand every link in every other
            // app to a window that only ever shows the one place.
            if !WebApp.on {
                Line(
                    "Open links from other apps",
                    isDefault ? "Satori is the default browser on this Mac" : "Mail, Slack and the rest still send links elsewhere"
                ) {
                    if isDefault {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 24)
                    } else {
                        Pill("Make default", filled: true) {
                            Links.becomeDefault { worked in
                                isDefault = Links.isDefault
                                browser.announce(worked && isDefault ? "Links now open here" : "macOS left it as it was")
                            }
                        }
                    }
                }
                Rule()
            }
            Line("Appearance", "Dark, light, or what the Mac does. Pages follow it too") {
                Segmented(options: Look.allCases.map { ($0, $0.title) }, selection: $prefs.look)
            }
            // A web app always wears its site's colour, and has no script
            // socket to offer.
            if !WebApp.on {
                Rule()
                Line("Adaptive", "The top bar takes the colour of the page. Turn off to keep it plain.") {
                    Switch(on: $prefs.adaptive)
                }
            }
            Rule()
            Line("Correct spelling as you type", "macOS autocorrect in pages. It capitalises for you.") {
                Switch(on: $prefs.autocorrect)
            }
            if !WebApp.on {
                Rule()
                Line("Let a script drive Satori", "A local socket for testing. Its tabs open beside yours with a flask on them and never take over. See ./bench") {
                    Switch(on: $prefs.bench)
                }
            }
            Rule()
            Line("Save downloads to", prefs.downloads.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                Pill("Change…") { chooseFolder() }
            }
            Rule()
            Line("Ask where to save each file") {
                Switch(on: $prefs.asksWhereToSave)
            }
        }
    }

    // MARK: - tabs

    private var tabs: some View {
        Card {
            Line("Tabs in a sidebar", "Down the left instead of across the top. Pull the edge to widen it. Double-click the edge to reset.") {
                Switch(on: Binding(
                    get: { prefs.sidebar },
                    set: { on in withAnimation(Motion.settle) { prefs.sidebar = on } }
                ))
            }
            Rule()
            Line("Sleep tabs you do not use", "After half an hour away they return where you left them. Pinned tabs, sound, calls and anything typed stay awake.") {
                Switch(on: $prefs.sleepsTabs)
            }
        }
    }

    // MARK: - passwords

    /// Says so when a password manager extension has taken the saving over.
    private var savingDetail: String {
        if !EXTENSIONS_HIDDEN, #available(macOS 15.4, *), let name = Extensions.shared.passwordSavingTakenBy {
            return "\(name) does the saving. It asked Satori not to offer."
        }
        return "Asked once per site, never again for a site you refuse"
    }

    private var passwords: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line("Your passwords", "In the macOS keychain, shown with Touch ID") {
                    Pill("Open…") {
                        browser.tuning = false
                        browser.managing = true
                    }
                }
                Rule()
                Line("Offer to save passwords", savingDetail) {
                    Switch(on: $prefs.savesPasswords)
                }
                Rule()
                Line("Fill in sign-ins", "Click a sign-in box and the accounts kept for the site hang from it") {
                    Switch(on: $prefs.fillsPasswords)
                }
                if !Vault.never.isEmpty {
                    Rule()
                    Line("Sites never asked", "\(Vault.never.count) sites told to stop offering") {
                        Pill("Forget") {
                            Vault.never = []
                            browser.announce("Every site can ask again")
                        }
                    }
                }
            }
            Card {
                Line("Bring yours in", "From Dia, Chrome, Arc, Brave or Edge on this Mac. Nothing leaves it.") {
                    Pill("Import…") {
                        browser.tuning = false
                        browser.managing = true
                    }
                }
            }
        }
    }

    // MARK: - search

    private var search: some View {
        Card {
            ForEach(Array(Engine.allCases.enumerated()), id: \.element.id) { index, engine in
                if index > 0 { Rule() }
                Line(engine.title) {
                    if prefs.engine == engine {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 24)
                    } else {
                        Pill("Use") { prefs.engine = engine }
                    }
                }
            }
        }
    }

    // MARK: - shortcuts

    /// Every keystroke, taught on the spot: press a combo to give it, esc to
    /// keep the old one, ⌫ to give the preset back.
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element.id) { index, action in
                    if index > 0 { Rule() }
                    Line(action.title) {
                        Button {
                            if prefs.recording == action {
                                recorder.stop(prefs: prefs)
                            } else {
                                recorder.start(action, prefs: prefs) { browser.objectWillChange.send() }
                            }
                        } label: {
                            Text(prefs.recording == action ? "Press keys…" : prefs.binding(for: action).display)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(prefs.recording == action ? Palette.ground : Palette.muted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(prefs.recording == action ? Palette.ink : Palette.wash, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !prefs.shortcutOverrides.isEmpty {
                Card {
                    Line("Back to every default") {
                        Pill("Reset all") {
                            prefs.shortcutOverrides = [:]
                            browser.objectWillChange.send()
                        }
                    }
                }
            }
        }
        .onDisappear { recorder.stop(prefs: prefs) }
    }

    // MARK: - privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line("Block ads and trackers", shield.trouble ?? "Third parties whose only job is to watch") {
                    Switch(on: $prefs.shielded)
                }
                if let trouble = shield.trouble {
                    Rule()
                    Line(trouble, "Nothing is blocked until this clears. Try again, or restart Satori.") {
                        Pill("Try again") { shield.compile() }
                    }
                }
                if let host = browser.hereHost, prefs.shielded, shield.trouble == nil {
                    Rule()
                    Line("Block on \(host)", "Turn off here if the site breaks. The page reloads.") {
                        Switch(on: Binding(
                            get: { !Shield.shared.isPaused(on: host) },
                            set: { on in
                                Shield.shared.pause(host, !on)
                                browser.reload()
                            }
                        ))
                    }
                }
                Rule()
                Line("Camera and microphone", "What each site was allowed or refused") {
                    Pill("Forget choices") { browser.forgetCaptureChoices() }
                }
            }
            Card {
                Line("History", "Every address you have been to") {
                    Pill("Clear") { browser.confirmClearHistory() }
                }
                Rule()
                Line("Cookies and sign-ins", "Signs you out of every site") {
                    Pill("Sign out of everything") { browser.clearSites() }
                }
                Rule()
                Line("Cache", "Only what was fetched to draw pages") {
                    Pill("Clear") { browser.clearCache() }
                }
            }
        }
    }

    // MARK: - about

    /// What this app is: the version people read, and the build Sparkle
    /// compares to tell newer from older.
    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppIcon(size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Satori")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: "by tretten · version \(Self.version) (\(Self.build))")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(.bottom, 2)

            Card {
                // A web app never runs Sparkle (see SatoriApp.init) — it is
                // rebuilt from main Satori instead, on that app's own launch.
                if !WebApp.on {
                    Line(
                        "Check for updates automatically",
                        prefs.automaticallyChecksForUpdates
                            ? "Checked every day, installed when Satori quits"
                            : "Only when you press the button below"
                    ) {
                        Switch(on: $prefs.automaticallyChecksForUpdates)
                    }
                    Rule()
                    Line("Updates", "A newer Satori downloads quietly and waits for a quit") {
                        Pill("Check for Updates…") {
                            UpdaterController.shared.checkForUpdates(nil)
                        }
                    }
                    Rule()
                }
                Line("Found something wrong?", "Opens a draft with the version already in it") {
                    Pill("Send Feedback") { Links.writeFeedback() }
                }
            }
        }
    }

    // MARK: - doing

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.downloads
        panel.prompt = "Use this folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.downloads = url
    }

    // MARK: - pieces
}

/// A keystroke and what it does. Pilled, the way the welcome shows them.
struct Shortcut: View {
    let keys: String
    let does: String
    var pill = false
    init(_ keys: String, _ does: String, pill: Bool = false) { self.keys = keys; self.does = does; self.pill = pill }

    var body: some View {
        if pill {
            HStack(spacing: 10) {
                Text(keys)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Palette.wash, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(minWidth: 44)
                Text(does).font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
        } else {
            HStack {
                Text(does)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(keys)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

/// A row of choices in a grey track, one of them lifted out in white. The
/// white slides to the one you pick rather than appearing there.
struct Segmented<Option: Hashable>: View {
    let options: [(Option, String)]
    @Binding var selection: Option

    @Namespace private var slide

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option, title in
                Text(title)
                    .font(.system(size: 11.5, weight: option == selection ? .medium : .regular))
                    .foregroundStyle(option == selection ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if option == selection {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.ground)
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "chosen", in: slide)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onTapGesture {
                        withAnimation(Motion.settle) { selection = option }
                    }
            }
        }
        .padding(2)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .animation(Motion.settle, value: selection)
    }
}

/// On or off, in ink rather than in blue.
struct Switch: View {
    @Binding var on: Bool

    var body: some View {
        Toggle("", isOn: $on)
            .toggleStyle(.switch)
            .tint(Palette.ink)
            .labelsHidden()
    }
}

/// A small capsule that does one thing. Outlined by default; filled in ink
/// when it is the thing you came here to press. Large for the welcome walk.
struct Pill: View {
    let title: String
    var filled = false
    var tint: Color = Palette.ink
    var large = false
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, filled: Bool = false, tint: Color = Palette.ink, large: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.tint = tint
        self.large = large
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: large ? 13 : 11.5, weight: large ? .medium : .regular))
                .foregroundStyle(filled ? Palette.ground : tint)
                .padding(.horizontal, large ? 16 : 10)
                .padding(.vertical, large ? 9 : 5)
                .background(filled ? Palette.ink : (hovering ? Palette.hover : Palette.ground), in: Capsule())
                .overlay(Capsule().strokeBorder(filled ? .clear : Palette.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}
