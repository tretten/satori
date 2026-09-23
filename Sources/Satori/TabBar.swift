import SwiftUI

/// Ink for the tab row when the site paints it: white on dark theme-colors,
/// the app's own ink everywhere else (nil).
private struct ChromeInkKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var chromeInk: Color? {
        get { self[ChromeInkKey.self] }
        set { self[ChromeInkKey.self] = newValue }
    }
}

/// The only chrome there is. Titles, one of them in a grey pill, and the pill
/// slides from the tab you left to the tab you picked rather than blinking out
/// of one and into the other.
struct TabBar: View {
    @ObservedObject var browser: Browser

    @Namespace private var pill

    /// Which tab is under the hand, where it started, and how far it has come.
    @State private var dragging: Tab.ID?
    @State private var from = 0
    @State private var travel: CGFloat = 0
    @State private var landing = false
    /// The plus only comes out when the pointer is in the row.
    @State private var nearby = false
    @State private var plussed = false
    /// How wide the doors at the far end are, extension buttons included.
    @State private var doors: CGFloat = 0

    var body: some View {
        // A GeometryReader is only here to measure the width. Its content is
        // put in a stack of its own and told to fill it: left to itself a
        // reader pins whatever it holds to the top corner, which is the row
        // riding at the very top of the strip while the traffic lights centre
        // themselves halfway down it.
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // The page's own color, wall to wall: the bar becomes the
                // site the way Dia does it. Ink for it comes down with the
                // row, white on dark colors.
                if let theme = browser.chromeTheme, let tint = Metrics.Theme.color(theme) {
                    Rectangle().fill(tint)
                }
                // The empty half of the strip is what you grab to move the
                // window; the tabs keep the run they sit on.
                DragStrip(reserved: Metrics.lights + Metrics.helm + Metrics.tabGap + run(in: geo.size.width) + Metrics.tabGap + Metrics.plusWidth, trailing: 26 + 24)
                // And the corner the lights sit in, which is title bar too —
                // the one stretch left to take hold of when tabs fill the row.
                DragStrip()
                    .frame(width: Metrics.lights)

                HStack(spacing: Metrics.tabGap) {
                    // Back, forward, reload, first thing after the lights —
                    // where hands coming from every other browser look for them.
                    Helm(browser: browser)
                        .padding(.trailing, 8)

                    // The tabs, in a run of their own. While they fit, it is
                    // exactly as wide as they are and nothing about the row
                    // changes. Past what the window holds at their narrowest
                    // it takes the room there is and scrolls inside its own
                    // edges — never under the lights, never over the doors —
                    // keeping the tab you are on in view.
                    ScrollViewReader { reader in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Metrics.tabGap) {
                                ForEach(Array(browser.tabs.enumerated()), id: \.element.id) { index, tab in
                                    // A pinned square moves among pinned squares, a title
                                    // among titles: each has its own stride.
                                    let step = (tab.pin != nil ? Metrics.pinWidth : width(in: geo.size.width)) + Metrics.tabGap
                                    let held = dragging == tab.id
                                    TabPill(
                                        browser: browser,
                                        prefs: browser.prefs,
                                        tab: tab,
                                        live: tab.id == browser.activeID,
                                        width: width(in: geo.size.width),
                                        room: geo.size.width - Metrics.lights - 12,
                                        pill: pill,
                                        close: { browser.close(tab) }
                                    )
                                    // The row reflows around it while the pill itself keeps
                                    // up with the hand: what it has travelled, less the
                                    // ground its new place has already given it.
                                    .offset(x: held ? travel - CGFloat(index - from) * step : 0)
                                    .zIndex(held ? 1 : 0)
                                    .shadow(color: .black.opacity(held ? 0.14 : 0), radius: 12, y: 4)
                                    .gesture(reorder(tab: tab, index: index, step: step))
                                    .id(tab.id)
                                }
                            }
                            .frame(height: Metrics.strip)
                        }
                        .scrollDisabled(!overflowing(in: geo.size.width))
                        .frame(width: run(in: geo.size.width))
                        .onAppear { reveal(reader, in: geo.size.width) }
                        .onChange(of: overflowing(in: geo.size.width)) { _, _ in reveal(reader, in: geo.size.width) }
                        .onChange(of: browser.activeID) { _, _ in reveal(reader, in: geo.size.width, gliding: true) }
                    }

                    // The way to a new page, right after the tabs rather than
                    // at the end of their run, so it is there however far the
                    // run has scrolled. Out of sight until the pointer is up here.
                    Button { browser.newTab() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(browser.chromeDark ? .white.opacity(0.65) : Palette.muted)
                            .frame(width: 15, height: 15)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(plussed ? Palette.hover : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { plussed = $0 }
                    .opacity(nearby ? 1 : 0)
                    .scaleEffect(nearby ? 1 : 0.7, anchor: .leading)
                    .allowsHitTesting(nearby)
                    .animation(Motion.settle, value: nearby)

                    Spacer(minLength: 0)

                    // The extensions and the bookmarks, at the far end
                    // of the row. The dropdown hangs from the last one.
                    HStack(spacing: Metrics.tabGap) {
                        ExtensionSlot()
                        Door(icon: "star", help: "Bookmarks") { browser.bookmarksOpen.toggle() }
                            .popover(isPresented: $browser.bookmarksOpen, arrowEdge: .bottom) {
                                BookmarksDropdown(browser: browser, bookmarks: browser.bookmarks)
                            }
                    }
                    .background {
                        GeometryReader { box in
                            Color.clear
                                .onAppear { doors = box.size.width }
                                .onChange(of: box.size.width) { _, width in doors = width }
                        }
                    }
                }
                .environment(\.chromeInk, browser.chromeDark ? .white : nil)
                // The traffic lights are the system's. The row starts after
                // them and stays there — nothing here moves to get out of
                // their way, because nothing here was ever in it.
                .padding(.leading, Metrics.lights)
                .padding(.trailing, 12)
                .coordinateSpace(name: "strip")
            }
        .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: Metrics.strip)
        .onHover { nearby = $0 }
        .border(Color.clear, width: 0)
        // A link dragged onto the row opens there.
        .onDrop(of: [.url, .text], isTargeted: $landing) { providers in
            browser.take(providers)
        }
        .background(landing ? Palette.hover : .clear)
        .animation(Motion.quick, value: landing)
        .animation(Motion.settle, value: browser.activeID)
        // The row makes room for the field on the same spring as everything
        // else. Without this the widths changed between one frame and the next
        // and the tabs appeared to jump aside.
        .animation(Motion.settle, value: browser.editingTab)
        .animation(Motion.settle, value: browser.tabs.map(\.id))
    }

    /// Pick a tab up and the others get out of its way as it passes them.
    private func reorder(tab: Tab, index: Int, step: CGFloat) -> some Gesture {
        // In the row's space, not the pill's — see the sidebar's grid for why.
        DragGesture(minimumDistance: 5, coordinateSpace: .named("strip"))
            .onChanged { value in
                if dragging != tab.id {
                    dragging = tab.id
                    from = index
                }
                travel = value.translation.width
                let moved = Int((travel / step).rounded())
                let target = min(max(0, from + moved), browser.tabs.count - 1)
                if target != index {
                    withAnimation(Motion.settle) { browser.move(tab, to: target) }
                }
            }
            .onEnded { _ in
                withAnimation(Motion.settle) {
                    dragging = nil
                    travel = 0
                }
            }
    }

    /// Brings the tab you are on into view once the run scrolls: at once
    /// when the window first shows it, on the strip's spring when you pick
    /// another. A turn of the run loop later, so the run has been laid out.
    private func reveal(_ reader: ScrollViewProxy, in strip: CGFloat, gliding: Bool = false) {
        guard overflowing(in: strip), let id = browser.activeID else { return }
        DispatchQueue.main.async {
            if gliding {
                withAnimation(Motion.settle) { reader.scrollTo(id) }
            } else {
                reader.scrollTo(id)
            }
        }
    }

    /// How wide the run of tabs is: as wide as the tabs while they fit, as
    /// wide as the room there is once they don't.
    private func run(in strip: CGFloat) -> CGFloat {
        min(content(in: strip), room(in: strip))
    }

    private func overflowing(in strip: CGFloat) -> Bool {
        content(in: strip) > room(in: strip) + 0.5
    }

    /// Everything in the run at the width the tabs get — and the address
    /// field's width for a tab being edited, which grows to take it.
    private func content(in strip: CGFloat) -> CGFloat {
        let each = width(in: strip)
        let pinned = CGFloat(browser.pinnedCount)
        let loose = CGFloat(browser.tabs.count) - pinned
        var total = pinned * Metrics.pinWidth + loose * each
            + CGFloat(max(0, browser.tabs.count - 1)) * Metrics.tabGap
        if let id = browser.editingTab, let tab = browser.tabs.first(where: { $0.id == id }) {
            total += min(340, strip - Metrics.lights - 12) - (tab.pin != nil ? Metrics.pinWidth : each)
        }
        return total
    }

    /// The strip, less the lights, the plus, the doors at the far end and
    /// the air around them. The doors are measured; until they have been,
    /// the three of the helm and the bookmarks stand in for them.
    private func room(in strip: CGFloat) -> CGFloat {
        let far = doors > 0 ? doors : 26
        return max(0, strip - Metrics.lights - 12 - Metrics.plusWidth - far - 3 * Metrics.tabGap)
    }

    /// Every loose tab is the same width, so the cross is always in the same
    /// place. Past a dozen or so they start giving ground; too narrow for a
    /// title they show their mark alone (Metrics.tabTitled), down to the
    /// mark and its air. Past that, the run scrolls. The pinned squares take
    /// their room off the top.
    private func width(in strip: CGFloat) -> CGFloat {
        let pinned = CGFloat(browser.pinnedCount)
        let loose = CGFloat(browser.tabs.count) - pinned
        guard loose > 0 else { return Metrics.tabWidth }
        let spent = pinned * Metrics.pinWidth
            + CGFloat(max(0, browser.tabs.count - 1)) * Metrics.tabGap
        return max(Metrics.tabMinWidth, min(Metrics.tabWidth, (room(in: strip) - spent) / loose))
    }
}

/// Back, forward, reload. They watch the live tab, not the window: whether
/// there is anywhere to go back to is the tab's to say, and it changes with
/// every page. Used here and, beside the traffic lights instead of at the
/// far end of the row, in the sidebar.
struct Helm: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if let tab = browser.active {
            Wheel(browser: browser, tab: tab)
        } else {
            // Nowhere to go and nothing to reload: the doors stay in place,
            // greyed, so the row doesn't shift when a tab arrives.
            HStack(spacing: 2) {
                Door(icon: "chevron.left") {}
                Door(icon: "chevron.right") {}
                Door(icon: "arrow.clockwise") {}
            }
            .opacity(0.3)
            .allowsHitTesting(false)
        }
    }

    private struct Wheel: View {
        let browser: Browser
        @ObservedObject var tab: Tab

        var body: some View {
            let back = !tab.isBlank && tab.canGoBack
            let forward = !tab.isBlank && tab.canGoForward
            HStack(spacing: 2) {
                Door(icon: "chevron.left", help: "Back   ⌘[") { browser.back() }
                    .disabled(!back)
                    .opacity(back ? 1 : 0.3)
                Door(icon: "chevron.right", help: "Forward   ⌘]") { browser.forward() }
                    .disabled(!forward)
                    .opacity(forward ? 1 : 0.3)
                // Reload, or stop while it is still coming.
                Door(
                    icon: tab.loading ? "xmark" : "arrow.clockwise",
                    help: tab.loading ? "Stop   ⌘." : "Reload   ⌘R"
                ) {
                    if tab.loading { tab.stop() } else { browser.reload() }
                }
                .disabled(tab.isBlank)
                .opacity(tab.isBlank ? 0.3 : 1)
            }
            .animation(Motion.quick, value: back)
            .animation(Motion.quick, value: forward)
            .animation(Motion.quick, value: tab.loading)
        }
    }
}

private struct TabPill: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let width: CGFloat
    /// How much of the strip there is, for the field that grows over it.
    let room: CGFloat
    let pill: Namespace.ID
    let close: () -> Void

    @State private var hovering = false
    @State private var shake: CGFloat = 0
    @Environment(\.chromeInk) private var chromeInk

    private var editing: Bool { browser.editingTab == tab.id }
    private var pinned: Bool { tab.pin != nil && !editing }
    /// Too narrow for a title: the site's mark alone, the title in the
    /// tooltip, and ⌘W or the menu to close it — a cross on something this
    /// small would be what a click to pick the tab lands on.
    private var compact: Bool { !editing && !pinned && width < Metrics.tabTitled }

    /// A pinned tab is a square, an edited one is a field, everything else is
    /// its share of what is left.
    private var span: CGFloat {
        if editing { return min(340, room) }
        return pinned ? Metrics.pinWidth : width
    }

    var body: some View {
        Group {
            if pinned {
                Group {
                    if browser.editingPin == tab.id {
                        PillField(browser: browser,
                            font: .systemFont(ofSize: 12, weight: .medium), alignment: .center,
                            text: { tab.pin ?? "" },
                            change: { browser.letter($0, for: tab) },
                            command: {
                                switch $0 {
                                case #selector(NSResponder.insertNewline(_:)),
                                     #selector(NSResponder.cancelOperation(_:)),
                                     #selector(NSResponder.insertTab(_:)):
                                    browser.endPinEdit()
                                    return true
                                default:
                                    return false
                                }
                            },
                            finish: { browser.endPinEdit() })
                    } else if prefs.glyph == .icons, let icon = tab.icon {
                        Mark(icon: icon, letter: tab.pin ?? "", size: 16, dim: tab.asleep)
                    } else {
                        Text(tab.pin ?? "")
                            .font(.system(size: 12, weight: .medium))
                            // A pin holding no page is still there and still
                            // yours; it just isn't costing anything.
                            .foregroundStyle(colour.opacity(tab.asleep ? 0.45 : 1))
                    }
                }
                .frame(width: 16, height: 16)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .frame(width: span)
            } else {
                loose
            }
        }
        .background { ground }
        .overlay {
            // An open field gets a frame of its own, so the tab being typed
            // in reads as the one thing on the row that wants the keyboard.
            if editing {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.3), lineWidth: 1)
            }
        }
        .modifier(Shake(travel: shake))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        // Never both at once.
        //
        // A view carrying a single tap *and* a double tap has to wait out the
        // system's double-click delay before it can conclude that a click was
        // single — and that delay is a preference, adjustable up to a second.
        // Which is exactly how long a tab took to come forward.
        //
        // So each tab carries one gesture. The pinned square you are already
        // on has nothing to do on a single click, so it takes the double one
        // and edits its letter; everything else answers the first click at
        // once. Change Letter in the menu covers the rest.
        .modifier(OneClick(double: live && pinned) {
            if live && pinned {
                browser.editLetter(tab)
            } else if live && !pinned {
                browser.beginTabEdit(tab)
            } else {
                browser.select(tab)
            }
        })
        .onHover { hovering = $0 }
        .contextMenu { TabMenu(browser: browser, tab: tab, close: close) }
        .help(pinned || compact ? tab.label : "")
        .animation(Motion.quick, value: hovering)
        .animation(Motion.settle, value: editing)
        .animation(Motion.settle, value: tab.pin)
        .onChange(of: browser.refusals) { _, _ in
            guard editing else { return }
            shake = 0
            withAnimation(.easeOut(duration: 0.5)) { shake = 1 }
        }
        // Arriving and leaving from the strip rather than from nowhere.
        .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
    }

    @ViewBuilder
    private var loose: some View {
        if compact {
            ZStack {
                if tab.loading {
                    Ring()
                } else {
                    Mark(icon: prefs.glyph == .icons ? tab.icon : nil, letter: tab.monogram, size: 15, dim: tab.asleep)
                }
            }
            .frame(width: 16, height: 16)
            .padding(.vertical, 6)
            .frame(width: span)
        } else {
            titled
        }
    }

    private var titled: some View {
        HStack(spacing: 6) {
            if editing {
                // The icon stays where it was — or a globe when the page has
                // none yet — so the tab keeps its face while it takes an address.
                if let icon = tab.icon {
                    Mark(icon: icon, letter: tab.monogram, size: 15, dim: tab.asleep)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 15, height: 15)
                }
                PillField(browser: browser,
                    text: { browser.tabDraft },
                    change: { browser.tabDraft = $0 },
                    command: {
                        switch $0 {
                        case #selector(NSResponder.insertNewline(_:)):
                            // Returning true keeps the field editing, which is what lets a
                            // refused address stay on screen instead of being thrown away.
                            browser.commitTabEdit()
                            return true
                        case #selector(NSResponder.cancelOperation(_:)):
                            browser.cancelTabEdit()
                            return true
                        default:
                            return false
                        }
                    },
                    finish: { browser.cancelTabEdit() })
                    .frame(height: 16)
            } else {
                if prefs.glyph == .icons, !tab.isBlank {
                    Mark(icon: tab.icon, letter: tab.monogram, size: 15)
                }
                if tab.bench {
                    // A script's tab, not yours.
                    Image(systemName: "flask")
                        .font(.system(size: 9))
                        .foregroundStyle(colour.opacity(0.7))
                }
                if tab.shy {
                    // Quiet, and only on the tabs that keep nothing.
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9))
                        .foregroundStyle(colour.opacity(0.7))
                }
                Text(tab.label)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(colour)
            }

            Spacer(minLength: 2)

            // Pinned to the right-hand end of the pill, not trailing the title.
            // One slot doing two jobs: the cross when the pointer is here, the
            // ring while the page is still coming, never both.
            ZStack {
                if hovering {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 15, height: 15)
                        .background(Palette.ink.opacity(0.07), in: Circle())
                        .transition(.opacity)
                } else if tab.loading {
                    Ring().transition(.opacity)
                } else if tab.noisy {
                    // Which tab the noise is coming from. ⌘⇧M stops it.
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Palette.muted)
                        .transition(.opacity)
                }
            }
            .frame(width: editing ? 0 : 15, height: 15)
            .opacity(editing ? 0 : 1)
            // The cross is 15 points across because that is how big it should
            // look. What you have to hit is the whole right-hand end of the
            // tab: an overlay is not laid out, so it can reach past its own
            // frame without moving anything that is.
            .overlay {
                if !editing {
                    Color.clear
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture { if hovering { close() } }
                }
            }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: tab.loading)
            .animation(Motion.quick, value: tab.noisy)
        }
        .padding(.leading, 11)
        .padding(.trailing, editing ? 11 : 7)
        .padding(.vertical, 6)
        .frame(width: span, alignment: .leading)
    }

    @ViewBuilder
    private var ground: some View {
        if live {
            // The grey fills from the left as you read down the page. It is
            // the one thing in the window that says how far in you are, and
            // it says it without adding anything to the window.
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.wash)
                // Not on a pinned square, nor a tab down to its mark. Thirty
                // points of grey filling from the left behind a single letter
                // says nothing about anything — it needs the width of a title
                // to read as progress at all.
                if !pinned && !compact {
                    Rectangle()
                        .fill(Palette.ink.opacity(0.055))
                        .frame(width: span * tab.reading)
                        .animation(.easeOut(duration: 0.15), value: tab.reading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .matchedGeometryEffect(id: "live", in: pill)
        } else if hovering {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.hover)
        } else if pinned {
            // A letter with nothing behind it reads as debris. A pinned tab
            // keeps a faint ground of its own so the block of them reads as
            // one thing.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.wash.opacity(0.55))
        }
    }

    private var colour: Color {
        if live { return ink }
        return hovering ? ink.opacity(0.7) : muted
    }

    private var ink: Color { chromeInk ?? Palette.ink }
    private var muted: Color { chromeInk?.opacity(0.65) ?? Palette.muted }
}

/// The address in a tab, the letter on a pin: one AppKit field for the two
/// places SwiftUI's selection paint is too loud — the system fills selected
/// text with accent colour, over a pale pill or a thirty-point square the
/// loudest thing on screen. Here it is a tenth of the ink. Same field,
/// different wiring.
struct PillField: NSViewRepresentable {
    @ObservedObject var browser: Browser
    var font: NSFont = .systemFont(ofSize: 12.5)
    var alignment: NSTextAlignment = .left
    var text: () -> String
    var change: (String) -> Void
    var command: (Selector) -> Bool
    var finish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = alignment
        field.font = font
        field.textColor = Palette.NS.ink
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.browser = browser
        coordinator.text = text
        coordinator.change = change
        coordinator.command = command
        coordinator.finish = finish
        let shown = text()
        if !coordinator.typing, field.stringValue != shown {
            field.stringValue = shown
        }
        guard !coordinator.claimed else { return }
        coordinator.claimed = true
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            guard let editor = field.currentEditor() as? NSTextView else { return }
            editor.selectedTextAttributes = [
                .backgroundColor: NSColor(Palette.ink.opacity(0.11)),
                .foregroundColor: Palette.NS.ink,
            ]
            editor.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var browser: Browser!
        var text: () -> String = { "" }
        var change: (String) -> Void = { _ in }
        var command: (Selector) -> Bool = { _ in false }
        var finish: () -> Void = {}
        var claimed = false
        var typing = false

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            typing = true
            change(field.stringValue)
            let shown = text()
            if field.stringValue != shown { field.stringValue = shown }
            typing = false
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy command: Selector
        ) -> Bool {
            self.command(command)
        }

        /// Clicking anywhere else is a way of saying never mind.
        func controlTextDidEndEditing(_ note: Notification) {
            let finish = finish
            DispatchQueue.main.async(execute: finish)
        }
    }
}

/// What a right-click on any tab offers, wherever the tab is drawn.
struct TabMenu: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let close: () -> Void

    var body: some View {
        if tab.pin == nil {
            Button("Pin") { browser.pin(tab) }
                .disabled(tab.isBlank)
        } else {
            Button("Change Letter") { browser.editLetter(tab) }
            Button("Unpin") { browser.unpin(tab) }
        }
        Divider()
        Button("Duplicate") {
            browser.select(tab)
            browser.duplicate()
        }
        .disabled(tab.isBlank)
        Button("Copy Address") {
            browser.select(tab)
            browser.copyAddress()
        }
        .disabled(tab.isBlank)
        Divider()
        Button("Close Tab", action: close)
        Button("Close Other Tabs") { browser.closeOthers(but: tab) }
            .disabled(browser.tabs.count < 2)
    }
}

/// One gesture or the other, never the two together.
struct OneClick: ViewModifier {
    let double: Bool
    let act: () -> Void

    func body(content: Content) -> some View {
        if double {
            content.onTapGesture(count: 2, perform: act)
        } else {
            content.onTapGesture(perform: act)
        }
    }
}

/// An almost-closed ring, turning — the same one the canvas app uses, small
/// enough to sit inside a tab without becoming the loudest thing in it.
struct Ring: View {
    var size: CGFloat = 10
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.78)
            .stroke(
                Palette.muted.opacity(0.7),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
