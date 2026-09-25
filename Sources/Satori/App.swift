import SwiftUI
import AppKit

// A window, a row of titles, and a field. Typing an address gets you a page;
// there is nothing else to learn and nothing else to press.

@main
struct SatoriApp: App {
    @StateObject private var browser = Browser()
    /// Links from other apps, and the Dock icon.
    @NSApplicationDelegateAdaptor(Links.self) private var links

    init() {
        // Boot Sparkle (daily auto-checks + one background check on launch) —
        // never in a web app, which would otherwise "update" itself into a
        // plain copy of Satori the moment Sparkle found a newer release.
        if !WebApp.on { _ = UpdaterController.shared }
        WebApp.stayAlive()
    }

    var body: some Scene {
        Window("Satori", id: "browser") {
            ContentView(browser: browser)
                .frame(minWidth: 640, minHeight: 420)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            // Quit asks first. The button routes through NSApp.terminate so
            // Cmd+Q, menu Quit and Dock Quit all land in
            // Links.applicationShouldTerminate and share one dialog.
            CommandGroup(after: .appInfo) {
                if !WebApp.on {
                    Button("Check for Updates…") {
                        UpdaterController.shared.checkForUpdates(nil)
                    }
                }
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit \(WebApp.name ?? "Satori")") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            // One window. Tabs are the only kind of "new" there is — except in
            // a web app, which has neither.
            CommandGroup(replacing: .newItem) {
                if WebApp.on {
                    Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                        .keyboardShortcut("w")
                } else {
                    Button("New Tab") { browser.newTab() }
                        .keyboardShortcut("t")
                    Button("New Private Tab") { browser.newShyTab() }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                    Button("Reopen Closed Tab") { browser.reopen() }
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                        .disabled(browser.ghosts.isEmpty)
                    Divider()
                    Button("Open Address…") { browser.edit() }
                        .keyboardShortcut("l")
                    Button("Make Web App…") { browser.makeWebApp() }
                        .disabled(browser.active?.isBlank ?? true)
                    Divider()
                    Button("Close Tab") { if let tab = browser.active { browser.close(tab) } }
                        .keyboardShortcut("w")
                }
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") { browser.printPage() }
                    .keyboardShortcut("p")
                    .disabled(browser.active?.isBlank ?? true)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find on Page…") { browser.openFind() }
                    .keyboardShortcut("f")
                    .disabled(browser.active?.isBlank ?? true)
                Button("Find Next") { browser.look(forward: true) }
                    .keyboardShortcut("g")
                    .disabled(!browser.finding)
                Button("Find Previous") { browser.look(forward: false) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(!browser.finding)
            }
            CommandGroup(replacing: .toolbar) {
                if !WebApp.on {
                    Toggle("Show Tabs in Sidebar", isOn: Binding(
                        get: { browser.prefs.sidebar },
                        set: { _ in browser.toggleSidebar() }
                    ))
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    Picker("Tabs show as", selection: Binding(
                        get: { browser.prefs.glyph },
                        set: { browser.prefs.glyph = $0 }
                    )) {
                        ForEach(Glyph.allCases) { glyph in
                            Text(glyph.title).tag(glyph)
                        }
                    }
                    Divider()
                }
                Button("Reload Page") { browser.reload() }
                    .keyboardShortcut("r")
                Button("Reading Mode") { browser.toggleReader() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Float Video") { browser.toggleFloat() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Hide Elements…") { browser.toggleHiding() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Hidden on This Site…") { browser.reviewing.toggle() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Divider()
                Button("Zoom In") { browser.zoom(by: 1.1) }
                    .keyboardShortcut("+")
                Button("Zoom Out") { browser.zoom(by: 1 / 1.1) }
                    .keyboardShortcut("-")
                Button("Actual Size") { browser.resetZoom() }
                    .keyboardShortcut("0")
            }
            if !WebApp.on {
                CommandMenu("Tabs") {
                    let back = browser.prefs.binding(for: .back)
                    let forward = browser.prefs.binding(for: .forward)
                    Button("Back") { browser.back() }
                        .keyboardShortcut(back.keyEquivalent, modifiers: back.eventModifiers)
                        .disabled(browser.active?.canGoBack != true)
                    Button("Forward") { browser.forward() }
                        .keyboardShortcut(forward.keyEquivalent, modifiers: forward.eventModifiers)
                        .disabled(browser.active?.canGoForward != true)
                    Divider()
                    Button("Next Tab") { browser.step(1) }
                        .keyboardShortcut("]", modifiers: [.command, .shift])
                    Button("Previous Tab") { browser.step(-1) }
                        .keyboardShortcut("[", modifiers: [.command, .shift])
                    Button("Satori Tabs…") { browser.summon() }
                        .keyboardShortcut("k")
                    Divider()
                    if let tab = browser.active {
                        if tab.pin == nil {
                            Button("Pin Tab") { browser.pin(tab) }
                                .disabled(tab.isBlank)
                        } else {
                            Button("Change Letter") { browser.editLetter(tab) }
                            Button("Unpin Tab") { browser.unpin(tab) }
                        }
                    }
                    Button("Duplicate Tab") { browser.duplicate() }
                        .keyboardShortcut("d")
                        .disabled(browser.active?.isBlank ?? true)
                    Button("Copy Address") { browser.copyAddress() }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .disabled(browser.active?.isBlank ?? true)
                    Button("Paste and Go") { browser.pasteAndGo() }
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                    Divider()
                    Button("Close Other Tabs") { if let tab = browser.active { browser.closeOthers(but: tab) } }
                        .disabled(browser.tabs.count < 2)
                    Button("Stop Sound in Tab") { browser.pauseMedia() }
                        .keyboardShortcut("m", modifiers: [.command, .shift])
                }
            }
            if !WebApp.on {
                CommandMenu("Bookmarks") {
                    Button("Bookmark This Page") { browser.bookmarkCurrent() }
                        .keyboardShortcut("b", modifiers: [.command, .shift])
                        .disabled(browser.active?.isBlank ?? true)
                    Button("Show Bookmarks…") { browser.bookmarking = true }
                    Divider()
                    BookmarkTree(nodes: browser.bookmarks.roots) { browser.visit($0) }
                }
            }
            CommandMenu("History") {
                Section("Recently Visited") {
                    ForEach(browser.recentlyVisited) { trace in
                        Button {
                            browser.open(trace.url, foreground: true)
                        } label: {
                            MenuLine(title: trace.title.isEmpty ? trace.key : trace.title, url: trace.url)
                        }
                    }
                }
                if !browser.ghosts.isEmpty {
                    Section("Recently Closed") {
                        ForEach(browser.ghosts.reversed().prefix(10)) { ghost in
                            Button {
                                browser.reopen(ghost)
                            } label: {
                                MenuLine(title: ghost.label, url: ghost.url)
                            }
                        }
                    }
                }
                Divider()
                Button("Show History…") { browser.recalling = true }
                    .keyboardShortcut("y")
                Button("Downloads…") { browser.hoarding = true }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
                Button("Clear History") { browser.confirmClearHistory() }
            }
            CommandGroup(after: .appSettings) {
                Button("Settings…") { browser.tuning = true }
                    .keyboardShortcut(",")
                if !WebApp.on {
                    Button("Welcome…") { browser.welcoming = true }
                    Button("Passwords…") { browser.managing = true }
                        .keyboardShortcut("l", modifiers: [.command, .option])
                }
            }
            CommandGroup(replacing: .help) {
                Button("Send Feedback…") { Links.writeFeedback() }
            }
        }
    }
}

/// The bookmarks, as menus within menus, for the menu bar.
private struct BookmarkTree: View {
    let nodes: [Bookmark]
    let open: (URL) -> Void

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                Menu(node.title) {
                    if let kids = node.children, !kids.isEmpty {
                        BookmarkTree(nodes: kids, open: open)
                    } else {
                        Text("Nothing here")
                    }
                }
            } else if let text = node.url, let url = URL(string: text) {
                Button(node.title) { open(url) }
            }
        }
    }
}

/// A page, as a line in a menu: its icon if one is known, and its name.
private struct MenuLine: View {
    let title: String
    let url: URL

    var body: some View {
        if let host = url.host()?.lowercased(),
           let icon = Favicons.shared.cached(host) {
            Label {
                Text(title)
            } icon: {
                Image(nsImage: MenuLine.small(icon))
            }
        } else {
            Text(title)
        }
    }

    /// The cached icon is sixty-four points across; a menu wants sixteen.
    private static func small(_ icon: NSImage) -> NSImage {
        let copy = icon.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}

struct ContentView: View {
    @ObservedObject var browser: Browser

    @State private var keys: Any?
    @State private var clicks: Any?
    @State private var window: NSWindow?
    @State private var resting: RestingLights?


    /// The window: room at the top, one stage for the page, and the row when
    /// there is one.
    private var window_: some View {
        ZStack(alignment: .top) {
            // Black while a page has the screen, so the frame of our own window
            // that survives the transition is not a white band across the top.
            (browser.active?.immersed == true ? Color.black : Palette.ground)

            HStack(spacing: 0) {
                // The column of tabs, in the way that has one. It takes the
                // full height, so the traffic lights sit in its own corner
                // rather than over the page.
                if sidebar {
                    SideBar(browser: browser, prefs: browser.prefs)
                        .transition(.move(edge: .leading))
                }

                VStack(spacing: 0) {
                    // Safari-Compact overlay: the page extends behind the 48pt
                    // strip (`stripReserve` is 0) and WebKit obscured insets
                    // (`Tab.desiredTopInset`, 48) shift normal flow AND fixed/sticky
                    // site headers below the bar while scrolled content slides
                    // beneath the translucent material. The TabBar stays above
                    // the page in the ZStack so hit-testing, DragStrip,
                    // lights, tab layout and safe-area handling are unchanged.
                    Color.clear
                        .frame(height: stripReserve)

                    // One stage, always.
                    if let tab = browser.active {
                        Page(tab: tab)
                            .overlay(alignment: .topTrailing) {
                                if browser.finding {
                                    FindBar(browser: browser)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .overlay(alignment: .topLeading) {
                                if let asked = browser.suggesting, asked.tab == tab.id {
                                    AccountList(browser: browser, asked: asked)
                                        .transition(.opacity)
                                }
                            }
                            .animation(Motion.quick, value: browser.suggesting)
                    } else {
                        Palette.ground
                    }
                }
                .padding(.horizontal, pagePad)
                .padding(.bottom, pagePad)
                .clipShape(RoundedRectangle(cornerRadius: pagePad > 0 ? Metrics.pageRadius : 0, style: .continuous))
            }

            if WebApp.on {
                if browser.active?.immersed != true {
                    AppStrip(browser: browser)
                }
            } else if !browser.prefs.sidebar, browser.active?.immersed != true {
                TabBar(browser: browser)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .animation(Motion.settle, value: browser.prefs.sidebar)
        .animation(.easeOut(duration: 0.12), value: browser.active?.immersed)
    }

    /// Everything that rises from the bottom edge to say one thing.
    private var bars: some View {
        VStack(spacing: 8) {
            announcement
            if let ask = browser.asking {
                captureAsking(ask)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let offer = browser.offering {
                keepAsking(offer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            StoreOffer(browser: browser)
            if browser.veiling {
                hint("Click to hide something   ⌘Z brings it back   esc done")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 30)
        .animation(Motion.settle, value: browser.veiling)
        .animation(Motion.settle, value: browser.asking)
        .animation(Motion.settle, value: browser.offering)
    }

    /// The address field: raised over a page by ⌘L or ⌘K, and standing on its
    /// own whenever a tab has nowhere to be yet.
    @ViewBuilder
    private var field: some View {
        if browser.fieldShowing {
            Omnibox(browser: browser, over: !(browser.active?.isBlank ?? true))
                // Centred on the page, not on the window. The column of tabs
                // is not what the field is standing over, and dimming it along
                // with the page says otherwise.
                .padding(.leading, sidebar ? browser.prefs.sideWidth : 0)
                // A fade only. Scaled along with the field, the veil over the
                // page shrank away from the window's edges and left the strip
                // uncovered until the very last frame.
                .transition(.opacity)
        }
    }

    /// The panels. All the same kind of thing, so they are built the same way.
    @ViewBuilder
    private var panels: some View {
        if browser.recalling {
            sheet { HistoryPanel(browser: browser) } close: { browser.recalling = false }
        }
        if browser.hoarding {
            sheet { DownloadsPanel(browser: browser, loot: browser.loot) }
                close: { browser.hoarding = false }
        }
        if browser.tuning {
            sheet { SettingsPanel(browser: browser, prefs: browser.prefs) }
                close: { browser.tuning = false }
        }
        if browser.bookmarking {
            sheet { BookmarksPanel(browser: browser, bookmarks: browser.bookmarks) }
                close: { browser.bookmarking = false }
        }
        if browser.welcoming {
            WelcomePanel(browser: browser, prefs: browser.prefs)
                .ignoresSafeArea()
        }
        if browser.managing {
            sheet { PasswordsPanel(browser: browser) } close: { browser.managing = false }
        }
        if browser.reviewing {
            // No dimming for this one: the whole point is to keep looking at
            // the page while the list offers to put things back on it.
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { browser.reviewing = false }
                HiddenPanel(browser: browser)
                    .padding(.top, Metrics.bar + 8)
                    .padding(.trailing, 14)
                    .transition(.scale(scale: 0.97, anchor: .topTrailing).combined(with: .opacity))
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    var body: some View {
        window_
            .overlay(alignment: .bottom) { bars }
            // Animated on its own layer only. Hung on the whole window, the
            // spring took in everything else that changed in the same
            // moment — the strip redrawing for the new state above all — and
            // that is where the opening stuttered.
            .overlay { field.animation(Motion.field, value: browser.fieldShowing) }
            .overlay { panels }
            .background(WindowSetup { window = $0; dress($0) })
            .onChange(of: browser.prefs.sidebar) { _, _ in
                DispatchQueue.main.async { measureLights() }
            }
            // Stepping away to another app: macOS draws its own resting
            // buttons, and on a light window they come out nearly white. Ours
            // go on in their place until the app comes back.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                measureLights()
                resting?.isHidden = false
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                resting?.isHidden = true
            }
            .onChange(of: browser.fieldShowing) { _, showing in
                if showing {
                    DispatchQueue.main.async { browser.askFocus() }
                } else {
                    handBack()
                }
            }
            .onChange(of: browser.activeID) { _, _ in handBack() }
            .animation(Motion.settle, value: browser.recalling)
            .animation(Motion.settle, value: browser.hoarding)
            .animation(Motion.settle, value: browser.tuning)
            .animation(Motion.settle, value: browser.welcoming)
            .animation(Motion.settle, value: browser.bookmarking)
            .animation(Motion.settle, value: browser.managing)
            .animation(Motion.settle, value: browser.reviewing)
        .onAppear {
            watchKeys()
            watchClicks()
            browser.askFocus()
            // Addresses from other apps have somewhere to go from here on.
            Links.hand(to: browser)
        }
    }

    /// Give the keyboard back to the page once the field is done with it.
    ///
    /// Nothing did this before, so after typing an address the window's first
    /// responder was a text field that no longer existed: typing went nowhere
    /// until you clicked the page. It also mattered more than it looked —
    /// WebAuthn refuses to run on a document that isn't focused, and so do a
    /// number of paste and shortcut handlers pages install for themselves.
    private func handBack() {
        guard !browser.fieldShowing else { return }
        DispatchQueue.main.async {
            guard let web = browser.active?.web, let window = web.window else { return }
            window.makeFirstResponder(web)
        }
    }

    // MARK: - the window

    /// A line that rises from the bottom, says one thing, and leaves.
    @ViewBuilder
    private var announcement: some View {
        if let text = browser.announcement {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Palette.ground, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(Motion.settle, value: browser.announcement)
        }
    }

    /// A page asking to see or hear you. Named by the site, in its own words,
    /// with the answer remembered so it is asked once and not every call.
    private func captureAsking(_ ask: Browser.CaptureAsk) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ask.wants == "microphone" ? "mic" : "video")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
            Text("\(ask.host) asks for your \(ask.wants)")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
            Button { browser.allowCapture() } label: {
                Text("Allow")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ground)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(Palette.ink, in: Capsule())
            }
            .buttonStyle(.plain)
            Button { browser.denyCapture() } label: {
                Text("Don't allow")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .background(Palette.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
    }

    /// Offered once, answered once. The password is never shown back to you —
    /// there is nothing to be learned from reading your own password.
    private func keepAsking(_ offer: Browser.Offer) -> some View {
        let login = offer.login
        return HStack(spacing: 12) {
            Text(offer.changed
                 ? "Update the password for \(login.user) on \(login.host)?"
                 : (login.user.isEmpty
                    ? "Save this password for \(login.host)?"
                    : "Save the password for \(login.user) on \(login.host)?"))
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Button(offer.changed ? "Update" : "Save") { browser.keepOffer() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ground)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Palette.ink, in: Capsule())
            Button("Not now") { browser.dropOffer() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
            if !offer.changed {
                Button("Never here") { browser.neverOffer() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .background(Palette.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
    }


    /// A dark pill, for the one mode this browser has. It stays up for as long
    /// as the mode does, which is how you know you are still in it.
    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ground.opacity(0.92))
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(Palette.ink.opacity(0.92), in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }

    /// The same dimmed ground and spring for every panel that floats over a
    /// page, so they read as one kind of thing.
    @ViewBuilder
    private func sheet<Panel: View>(
        @ViewBuilder _ panel: () -> Panel,
        close: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            panel()
                .transition(.scale(scale: 0.97).combined(with: .opacity))
        }
        .transition(.opacity)
    }

    /// True while the tabs are down the left.
    private var sidebar: Bool {
        !WebApp.on && browser.prefs.sidebar && browser.active?.immersed != true
    }

    /// The page floats on the ground with air around it — except while one
    /// has the screen, when there is no frame left to float in.
    private var pagePad: CGFloat {
        browser.active?.immersed == true ? 0 : Metrics.pageInset
    }

    /// How much vertical room the page leaves for the top strip.
    ///
    /// Always 0: Safari-Compact overlay in every state — the page extends
    /// behind the 48pt strip whether the bar is tinted opaque or untinted
    /// translucent. Content offset comes from WebKit obscured insets
    /// (`Tab.desiredTopInset`), which shift normal flow AND fixed/sticky headers
    /// below the bar while scrolled content slides beneath it. Keeping the
    /// reserve constant (instead of 48 tinted / 0 untinted) means tint flips
    /// change only the bar's material, never the viewport geometry — no
    /// layout jumps when a page reports a new theme colour or Adaptive is
    /// toggled. Materials, tint computation and the Adaptive gate are
    /// untouched. The spacer is kept (at 0 height) as the layout anchor.
    ///
    /// Rules: 0 everywhere — normal, tinted, untinted, blank, sleeping,
    /// floating, sidebar, immersed. Sidebar and immersed have no strip; the
    /// rest share one overlay geometry so loading, waking, floating home
    /// and tint transitions never shift layout.
    ///
    /// Reduce Transparency keeps working via the material's own default
    /// fallback (opaque fill).
    /// Nothing in the browser, where the page runs up behind the strip. A
    /// web app's page starts below it instead: sites built as one fixed
    /// screen (Telegram, Slack) never scroll, so an obscured inset can't
    /// move them and their top would sit under the bar.
    private var stripReserve: CGFloat {
        WebApp.on && browser.active?.immersed != true ? Metrics.bar : 0
    }

    /// The obscured top inset lives in `Tab.desiredTopInset` (single source
    /// of truth, resolved live by the stage). No snapshot is computed here:
    /// a value captured at render time used to race `Tab.applyTopInsetNow`
    /// and overwrite the correct 48 with a stale 0 on a later layout.

    /// Put the resting circles in the title bar, exactly over the buttons,
    /// for when the app is behind: macOS's own resting buttons come out
    /// nearly white on a light window, so these cover them until it's back.
    private func measureLights() {
        guard let window,
              let close = window.standardWindowButton(.closeButton),
              !close.isHidden,
              let titlebar = close.superview
        else {
            resting?.isHidden = true
            return
        }

        let view = resting ?? RestingLights()
        if view.superview !== titlebar {
            view.frame = titlebar.bounds
            view.autoresizingMask = [.width, .height]
            titlebar.addSubview(view, positioned: .above, relativeTo: nil)
            resting = view
        }
        view.spots = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
            .map { $0.convert($0.bounds, to: titlebar) }
        view.isHidden = NSApp.isActive
    }

    private func dress(_ window: NSWindow) {
        Links.window = window
        // Light or dark is the app's to say (Settings › Appearance); the
        // window only has to be the ground colour that goes with it.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Palette.NS.ground
        // The strip does the dragging, so the page underneath can't be grabbed
        // by accident while selecting text.
        window.isMovableByWindowBackground = false
        // The transparent title bar's container is 48pt tall, full-width, and
        // kept above the content (below) so the traffic lights paint over it.
        // Left movable, AppKit starts a native title-bar drag on any press-drag
        // in that band — including on a tab — which beats the SwiftUI reorder
        // gesture. The custom DragStrip stays the sole mover for empty areas.
        window.isMovable = false
        // Where you left it, at the size you left it. A test run keeps its
        // own: the name lives in the app's standard defaults, which every
        // copy shares, and a probe resized for a test once changed the size
        // the real window came back at.
        window.setFrameAutosaveName(Store.world.map { "satori (\($0))" } ?? "satori")

        // The traffic lights set in from the corner and centred in the strip's
        // height, in both modes, without a toolbar's rounder corners — see
        // Lights.swift. The column's first row is the strip's height too, so
        // its three doors sit on the lights' line.
        Lights.keep(window) { measureLights() }
        DispatchQueue.main.async { measureLights() }

        // The traffic lights are drawn — measured, they paint themselves — but
        // the window shows white where they are. The content view fills the
        // whole window, title bar included, and its layer was compositing over
        // the title bar's own. AppKit's subview order said otherwise; Core
        // Animation is the one actually deciding, so it is told directly.
        DispatchQueue.main.async {
            guard let close = window.standardWindowButton(.closeButton),
                  let container = close.superview?.superview,
                  let content = window.contentView,
                  let frame = content.superview
            else { return }
            frame.addSubview(container, positioned: .above, relativeTo: content)
            container.wantsLayer = true
            container.layer?.zPosition = 10
        }
    }

    // MARK: - keys

    /// A web view takes first responder and keeps most of the keyboard, so the
    /// shortcuts are caught before the event ever reaches it. The menu carries
    /// the same commands for anyone looking for them, and never sees these
    /// keystrokes because this runs first.
    private func watchKeys() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else {
                // ⌘ let go of ends a ⌘K walk, wherever it stopped.
                if !event.modifierFlags.contains(.command) { browser.landSummon() }
                return event
            }
            return take(event) ? nil : event
        }
    }

    /// Side buttons window-wide, including over the page: this monitor runs
    /// before the responder chain so it owns buttons 3/4 everywhere in the
    /// main window and sends them to the same back()/forward() PageView
    /// answers with on its own path. Only buttons 3 (back) and 4 (forward)
    /// are taken; middle-click (2) and anything else pass through untouched.
    /// While a native text field is being edited the press is left alone so
    /// typing is never interrupted; menus likewise keep their events.
    private func watchClicks() {
        guard clicks == nil else { return }
        clicks = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { event in
            takeClick(event)
        }
    }

    private func takeClick(_ event: NSEvent) -> NSEvent? {
        guard event.buttonNumber == 3 || event.buttonNumber == 4 else { return event }
        // Main browser window only: side presses in the floating video window
        // keep their events, so they never navigate the main tab.
        if let target = event.window, let main = window ?? Links.window, target !== main { return event }
        if let win = event.window ?? NSApp.keyWindow,
           let first = win.firstResponder,
           first is NSText || first is NSTextView { return event }
        if event.type == .otherMouseDown {
            // The same touch PageView reports on its own path, so the sleep
            // cover comes off identically whichever owns the press.
            browser.active?.uncover()
            if event.buttonNumber == 3 { browser.back() } else { browser.forward() }
        }
        return nil
    }

    private func take(_ event: NSEvent) -> Bool {
        // A combo being taught goes straight to the recorder: teaching one
        // must never fire one.
        guard browser.prefs.recording == nil else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Escape puts the page back. On a blank tab there is no page to put
        // back, so it belongs to whatever else wants it.
        if event.keyCode == 53 {
            if browser.tuning {
                browser.tuning = false
                return true
            }
            if browser.bookmarking {
                browser.bookmarking = false
                return true
            }
            if browser.managing {
                browser.managing = false
                return true
            }
            if browser.suggesting != nil {
                browser.dropChoice()
                return true
            }
            if browser.veiling {
                browser.toggleHiding()
                return true
            }
            if browser.reviewing {
                browser.reviewing = false
                return true
            }
            if browser.finding {
                browser.closeFind()
                return true
            }
            if browser.recalling {
                browser.recalling = false
                return true
            }
            if browser.hoarding {
                browser.hoarding = false
                return true
            }
            // One step at a time: the list first, then the field.
            if browser.picked != nil {
                browser.picked = nil
                return true
            }
            guard browser.editing, browser.active?.isBlank == false else { return false }
            browser.dismiss()
            return true
        }

        // Tab walks the row and comes round to the first again; ⇧Tab walks it
        // the other way. Other browsers give Tab to the page — here the row is
        // the only thing there is to move between, so it gets the key.
        //
        // Except while an address is being typed. Then the list under the field
        // is what there is to move through, and Return takes whatever the walk
        // landed on.
        if event.keyCode == 48, !flags.contains(.command), !flags.contains(.option), !WebApp.on {
            // Filling something in on the page: the key belongs to the field,
            // which may well be offering a completion to take with it.
            if !browser.fieldShowing, browser.active?.typing == true { return false }
            if browser.fieldShowing, !browser.offers.isEmpty {
                browser.walk(flags.contains(.shift) ? -1 : 1)
                return true
            }
            browser.step(flags.contains(.shift) ? -1 : 1)
            return true
        }

        // A shortcut an extension registered — ⌥⇧D, ⌃⇧Y — before ours, since
        // none of ours use those.
        if #available(macOS 15.4, *), !flags.intersection([.command, .option, .control]).isEmpty,
           Extensions.shared.take(event) {
            return true
        }

        guard flags.contains(.command) else { return false }
        let shifted = flags.contains(.shift)

        // Anything with ⌥ or ⌃ on top is somebody else's.
        guard !flags.contains(.option), !flags.contains(.control) else { return false }

        // A web app is one site in one window: what's left of the browser's
        // keys is what makes sense for a single page. The rest go to the page
        // itself, which may well have a ⌘K of its own.
        if WebApp.on {
            let kept: Set<String> = ["f", "g", "p", "=", "+", "-", "0", "r", "[", "]", ",", "j", "w"]
            let arrow = event.keyCode == 123 || event.keyCode == 124
            guard kept.contains(key) || arrow, !(shifted && ["[", "]", "w"].contains(key)) else { return false }
            if key == "w" {
                NSApp.keyWindow?.performClose(nil)
                return true
            }
        }

        // A taught combo wins over every default below it.
        if let taught = browser.prefs.overrideMatch(key: key, flags: flags) {
            taught.perform(on: browser)
            return true
        }

        switch key {
        case "t" where !shifted:
            browser.newTab()
        case "t" where shifted:
            browser.reopen()
        case "c" where shifted:
            browser.copyAddress()
        case "d" where !shifted:
            browser.duplicate()
        case "n" where shifted:
            browser.newShyTab()
        case "y" where !shifted:
            browser.recalling.toggle()
        case "j" where shifted:
            browser.hoarding.toggle()
        case "v" where shifted:
            browser.pasteAndGo()
        case "p" where !shifted:
            browser.printPage()
        case "f" where !shifted:
            browser.openFind()
        case "g":
            browser.look(forward: !shifted)
        case "m" where shifted:
            browser.pauseMedia()
        case "p" where shifted:
            browser.toggleFloat()
        case "k" where !shifted:
            // Held down, ⌘K walks the list a step at a time; letting go of ⌘
            // takes wherever it stopped.
            if browser.editing, !browser.offers.isEmpty {
                browser.stepSummon()
            } else {
                browser.summon()
            }
        case "s" where shifted:
            browser.toggleSidebar()
        case "b" where shifted:
            browser.bookmarkCurrent()
        case "," where !shifted:
            browser.tuning.toggle()
        case "h" where shifted:
            browser.toggleHiding()
        case "u" where shifted:
            browser.reviewing.toggle()
        case "z" where !shifted:
            // Only while pointing. Everywhere else undo belongs to the page.
            guard browser.veiling else { return false }
            browser.undoHiding()
        // ⌘+ arrives as "=" or "+" depending on the keyboard; both mean bigger.
        case "=", "+":
            browser.zoom(by: 1.1)
        case "-":
            browser.zoom(by: 1 / 1.1)
        case "0":
            browser.resetZoom()
        case "w" where !shifted:
            if let tab = browser.active { browser.close(tab) }
        case "l" where !shifted:
            browser.edit()
        case "r" where !shifted:
            browser.reload()
        case "r" where shifted:
            browser.toggleReader()
        case "[":
            shifted ? browser.step(-1) : browser.back()
        case "]":
            shifted ? browser.step(1) : browser.forward()
        default:
            // ⌘1 through ⌘9: the ninth is the last one, however many there are.
            if let number = Int(key), (1...9).contains(number), !shifted {
                browser.select(index: number == 9 ? browser.tabs.count - 1 : number - 1)
                return true
            }
            // ⌘← and ⌘→, for hands that never learned the brackets.
            if event.keyCode == 123 { browser.back(); return true }
            if event.keyCode == 124 { browser.forward(); return true }
            return false
        }
        return true
    }
}


/// A web app's whole top edge: the site's own colour, the traffic lights, and
/// somewhere to take hold of the window. No tabs — it is one site — and a
/// click on it takes the page back to its top, as the browser's strip does.
private struct AppStrip: View {
    @ObservedObject var browser: Browser

    var body: some View {
        HStack(spacing: 0) {
            DragStrip(onClick: { browser.active?.scrollToTop() })
            HStack(spacing: Metrics.tabGap) {
                // There from the first file on. It goes where the file went:
                // a web app has no downloads list worth a panel of its own.
                if !browser.downloading.isEmpty || !browser.loot.kept.isEmpty {
                    Door(
                        icon: browser.downloading.isEmpty ? "arrow.down.circle" : "arrow.down.circle.fill",
                        help: "Show in Finder",
                        tint: browser.themeColor
                    ) {
                        if let last = browser.loot.kept.first(where: \.stillThere) {
                            browser.loot.reveal(last)
                        } else {
                            NSWorkspace.shared.open(browser.prefs.downloads)
                        }
                    }
                }
                Door(icon: "command", help: "Settings   ⌘,", tint: browser.themeColor) { browser.tuning.toggle() }
            }
            .padding(.trailing, 12)
            .offset(y: Metrics.barDrop)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.bar)
        // The page's own title, centred as a window's is. Sites put what is
        // worth a glance there — unread counts, who is typing.
        .overlay {
            if let tab = browser.active {
                PageTitle(tab: tab, tint: browser.themeColor)
                    .padding(.horizontal, Metrics.lights + 12)
                    .offset(y: Metrics.barDrop)
                    .allowsHitTesting(false)
            }
        }
        // The colour of the page's own top edge; glass until it has been read.
        .background {
            if let tint = browser.themeColor {
                tint.color
            } else {
                Glass()
            }
        }
        .overlay(alignment: .bottom) {
            if let tint = browser.themeColor {
                // The bar's colour is the page's edge averaged, and a wallpaper
                // or a gradient is never quite its own average. A short fade
                // over the top of the page takes the seam away.
                // The same fill as the bar, faded by a mask rather than drawn
                // as a gradient of its own: a gradient's colours don't ease
                // the way a fill does, and the two drifted apart mid-change.
                Rectangle().fill(tint.color)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 18)
                    .offset(y: 18)
                    .allowsHitTesting(false)
            } else {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                    .allowsHitTesting(false)
            }
        }
        // The page's own fades run in the compositor, where a picture of the
        // page can't see them: a read gets the colour before and then the
        // colour after. So the bar does the fade itself, over about as long
        // as a page's overlay takes to come in.
        .animation(.easeInOut(duration: 0.15), value: browser.themeColor)
    }
}

/// A tab's title, watched on its own so the bar redraws when the page
/// changes it and at no other time.
private struct PageTitle: View {
    @ObservedObject var tab: Tab
    let tint: Tint?

    var body: some View {
        Text(tab.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.foreground(on: tint))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// The title bar's own material, blending with what is behind the window.
private struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .titlebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
