import SwiftUI

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A GeometryReader is only here to measure the width. Its content is
        // put in a stack of its own and told to fill it: left to itself a
        // reader pins whatever it holds to the top corner, which is the row
        // riding at the very top of the strip while the traffic lights centre
        // themselves halfway down it.
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // The empty half of the strip is what you grab to move the
                // window; the tabs keep the run they sit on. Explicit full-size
                // frames: without one the representable's size is ambiguous and
                // empty-area drags would fall back to the title bar (disabled
                // in dress(_:) so tab drags can't move the window).
                // A click on it takes the page back to its top.
                DragStrip(reserved: Metrics.lights + Metrics.helm + Metrics.tabGap + run(in: geo.size.width) + Metrics.tabGap + Metrics.plusWidth, trailing: 26 + 24, onClick: { browser.active?.scrollToTop() })
                    .frame(width: geo.size.width, height: Metrics.strip)
                // And the corner the lights sit in, which is title bar too —
                // the one stretch left to take hold of when tabs fill the row.
                DragStrip(onClick: { browser.active?.scrollToTop() })
                    .frame(width: Metrics.lights, height: Metrics.strip)

                HStack(spacing: Metrics.tabGap) {
                    // Back, forward, first thing after the lights —
                    // where hands coming from every other browser look for them.
                    Helm(browser: browser, tint: browser.themeColor)
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
                                    .highPriorityGesture(reorder(tab: tab, index: index, step: step))
                                    .id(tab.id)
                                }
                            }
                            .frame(height: Metrics.strip)
                        }
                        .scrollDisabled(!overflowing(in: geo.size.width))
                        .frame(width: run(in: geo.size.width))
                        .onAppear { reveal(reader, in: geo.size.width) }
                        .onChange(of: overflowing(in: geo.size.width)) { _, _ in revealSoon(reader, in: geo.size.width) }
                        .onChange(of: browser.activeID) { _, _ in revealSoon(reader, in: geo.size.width, gliding: true) }
                    }

                    // The way to a new page, right after the tabs rather than
                    // at the end of their run, so it is there however far the
                    // run has scrolled. Out of sight until the pointer is up here.
                    Button { browser.newTab() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.foreground(on: browser.themeColor, dimmed: true))
                            .frame(width: 15, height: 15)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(plussed ? (browser.themeColor != nil ? Palette.foreground(on: browser.themeColor).opacity(0.12) : Palette.hover) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New tab")
                    .onHover { plussed = $0 }
                    .opacity(nearby ? 1 : 0)
                    .scaleEffect(nearby ? 1 : 0.7, anchor: .leading)
                    .allowsHitTesting(nearby)
                    .animation(Motion.settle, value: nearby)

                    Spacer(minLength: 0)

                    // The extensions, the bookmarks and the settings, at the
                    // far end of the row. The dropdown hangs from the star.
                    HStack(spacing: Metrics.tabGap) {
                        ExtensionSlot(tint: browser.themeColor)
                            // Icons decode in Extensions.buttons when the row re-evaluates.
                            // Kept out of the insertion transaction so `+` never waits on them.
                            .transaction { $0.animation = nil }
                        // There from the first file on, while the list is
                        // worth opening. Filled while one is still coming.
                        if !browser.downloading.isEmpty || !browser.loot.kept.isEmpty {
                            Door(
                                icon: browser.downloading.isEmpty ? "arrow.down.circle" : "arrow.down.circle.fill",
                                help: "Downloads   ⇧⌘J",
                                tint: browser.themeColor
                            ) { browser.hoarding.toggle() }
                        }
                        Door(icon: "command", help: "Settings   ⌘,", tint: browser.themeColor) { browser.tuning.toggle() }
                    }
                    .background {
                        GeometryReader { box in
                            Color.clear
                                .onAppear { doors = box.size.width }
                                .onChange(of: box.size.width) { _, width in doors = width }
                        }
                    }
                }
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
        // Strip ground, gated on tint only: tinted wears the page's own
        // opaque colour so the strip reads as the page continuing upward;
        // untinted (Adaptive OFF / no page colour) is near-opaque ground
        // (Palette.ground at 0.95: effectively no blur, only faint
        // show-through) so the strip reads separated with a hint of depth.
        // Palette.ground follows light/dark automatically; near-opaque is
        // already fine under Reduce Transparency -- no extra handling here.
        .background {
            if let tint = browser.themeColor {
                tint.color
            } else {
                Rectangle().fill(Palette.ground.opacity(0.95))
            }
        }
        // Hairline only when untinted: on a tint it would cut the
        // page-continuing illusion; on the material it separates chrome
        // from content (Side.swift:88-90).
        .overlay(alignment: .bottom) {
            if browser.themeColor == nil {
                Rectangle().fill(Palette.hairline).frame(height: 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            StripProgress(browser: browser)
                .allowsHitTesting(false)
        }
        .animation(Motion.quick, value: landing)
        // No slide for the transaction that activates a just-inserted tab:
        // the old pill sliding while the new pill transitions in is the
        // double-pill ghost. Switching, reorder and the rest still glide.
        .animation(browser.insertedID == nil ? Motion.settle : nil, value: browser.activeID)
        .animation(Motion.quick, value: browser.themeColor)
        // No animation on tab-list identity: it pulled every pill, the helm,
        // the plus and the extension icons into one spring on each insertion,
        // which froze `+`. Arrival still reads via the pill transition and
        // the live-pill slide (activeID above); reorder animates explicitly.
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

    /// The reveal, sequenced past a `+` insertion: scrolling on the strip's
    /// spring in the same transaction as the new pill's appear transition
    /// fights it and reads as a stutter. Insertions glide once settled;
    /// switches glide at once. Reduce Motion never glides (see `reveal`).
    private func revealSoon(_ reader: ScrollViewProxy, in strip: CGFloat, gliding: Bool = false) {
        guard browser.insertedID == nil else {
            let id = browser.activeID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard browser.activeID == id else { return }
                reveal(reader, in: strip, gliding: true)
            }
            return
        }
        reveal(reader, in: strip, gliding: gliding)
    }

    /// Brings the tab you are on into view once the run scrolls: at once
    /// when the window first shows it, on the strip's spring when you pick
    /// another. A turn of the run loop later, so the run has been laid out.
    private func reveal(_ reader: ScrollViewProxy, in strip: CGFloat, gliding: Bool = false) {
        guard overflowing(in: strip), let id = browser.activeID else { return }
        DispatchQueue.main.async {
            if gliding, !reduceMotion {
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

    /// Everything in the run at the width the tabs get.
    private func content(in strip: CGFloat) -> CGFloat {
        let each = width(in: strip)
        let pinned = CGFloat(browser.pinnedCount)
        let loose = CGFloat(browser.tabs.count) - pinned
        return pinned * Metrics.pinWidth + loose * each
            + CGFloat(max(0, browser.tabs.count - 1)) * Metrics.tabGap
    }

    /// The strip, less the lights, the plus, the doors at the far end and
    /// the air around them. The doors are measured; until they have been,
    /// the two of the helm and the bookmarks stand in for them.
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

/// Page-load progress: a thin bar along the strip's bottom edge, width
/// proportional to the active tab's load progress, in the system accent
/// colour. Outside the tint foreground system on purpose — never
/// Palette.foreground, never a tint ground.
///
/// Shown while the active tab is loading; hidden once progress reaches 1 or
/// loading ends. The outer view follows tab switches (browser.activeID); the
/// inner view follows that tab's loading/progress, so a switch from a loading
/// tab to an idle one hides at once and a fast load that finished before the
/// next render never appears (no flicker, no stuck bar).
private struct StripProgress: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if let tab = browser.active {
            StripProgressInner(tab: tab)
        } else {
            Color.clear.frame(height: 2)
        }
    }
}

private struct StripProgressInner: View {
    @ObservedObject var tab: Tab

    var body: some View {
        GeometryReader { geo in
            if tab.loading && tab.progress < 1 {
                Rectangle()
                    .fill(Color(nsColor: .controlAccentColor))
                    .opacity(0.65)
                    .shadow(color: Color(nsColor: .controlAccentColor).opacity(0.5), radius: 4, y: 0)
                    .frame(width: geo.size.width * min(max(tab.progress, 0), 1), height: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            } else {
                Color.clear
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}

/// Back, forward. They watch the live tab, not the window: whether
/// there is anywhere to go back to is the tab's to say, and it changes with
/// every page. Used here and, beside the traffic lights instead of at the
/// far end of the row, in the sidebar. Reload/stop lives in the live tab
/// pill on hover, with Cmd+R / Cmd+. through the existing action paths.
struct Helm: View {
    @ObservedObject var browser: Browser
    /// Website tint behind the top bar. Nil keeps the existing Palette
    /// doors; the sidebar uses the default.
    var tint: Tint? = nil

    var body: some View {
        if let tab = browser.active {
            Wheel(browser: browser, tab: tab, tint: tint)
        } else {
            // Nowhere to go: the doors stay in place, greyed, so the row
            // doesn't shift when a tab arrives.
            HStack(spacing: 2) {
                Door(icon: "chevron.left", tint: tint) {}
                Door(icon: "chevron.right", tint: tint) {}
            }
            .opacity(0.3)
            .allowsHitTesting(false)
        }
    }

    private struct Wheel: View {
        let browser: Browser
        @ObservedObject var tab: Tab
        var tint: Tint? = nil

        var body: some View {
            let back = !tab.isBlank && tab.canGoBack
            let forward = !tab.isBlank && tab.canGoForward
            HStack(spacing: 2) {
                Door(icon: "chevron.left", help: "Back   ⌘[", tint: tint) { browser.back() }
                    .disabled(!back)
                    .opacity(back ? 1 : 0.3)
                Door(icon: "chevron.right", help: "Forward   ⌘]", tint: tint) { browser.forward() }
                    .disabled(!forward)
                    .opacity(forward ? 1 : 0.3)
            }
            .animation(Motion.quick, value: back)
            .animation(Motion.quick, value: forward)
        }
    }
}

private struct TabPill: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let width: CGFloat
    /// How much of the strip there is.
    let room: CGFloat
    let pill: Namespace.ID
    let close: () -> Void

    @State private var hovering = false
    /// When the last single click landed, for telling a double-click apart
    /// from two separate clicks without making a single click wait out the
    /// system's double-click delay first (see the tap below).
    @State private var lastTap = Date.distantPast

    private var pinned: Bool { tab.pin != nil }
    /// Too narrow for a title: the site's mark alone, the title in the
    /// tooltip, and ⌘W or the menu to close it — a cross on something this
    /// small would be what a click to pick the tab lands on.
    private var compact: Bool { !pinned && width < Metrics.tabTitled }

    /// A pinned tab is a square, everything else is its share of what is left.
    private var span: CGFloat {
        pinned ? Metrics.pinWidth : width
    }

    var body: some View {
        Group {
            if pinned {
                Group {
                    if browser.editingPin == tab.id {
                        PillField(browser: browser,
                            tint: browser.themeColor,
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
                        Mark(icon: icon, letter: tab.pin ?? "", size: 16, dim: tab.asleep, tint: browser.themeColor)
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
                .padding(.vertical, 7)
                .frame(width: span)
            } else {
                loose
            }
        }
        .background { ground }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        // One tap gesture only, so picking a tab never waits out the system's
        // double-click delay. A click on the tab already showing raises the
        // centred address field; on any other, it picks the tab. Scrolling to
        // the top lives on the empty strip. A pinned square's double-click
        // (see `lastTap`) still edits its letter, taking the field back down.
        .onTapGesture {
            let now = Date()
            let double = now.timeIntervalSince(lastTap) < 0.4
            lastTap = now
            if double && pinned {
                browser.dismiss()
                browser.editLetter(tab)
                return
            }
            if live {
                browser.edit()
            } else {
                browser.select(tab)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { TabMenu(browser: browser, tab: tab, close: close) }
        .help(pinned || compact ? tab.label : "")
        .accessibilityHint(live ? "Opens the address field." : "Shows this tab.")
        .animation(Motion.quick, value: hovering)
        .animation(Motion.settle, value: tab.pin)
        // Arriving and leaving from the strip rather than from nowhere.
        .transition(.scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
    }

    @ViewBuilder
    private var loose: some View {
        if compact {
            ZStack {
                if tab.loading {
                    Ring(tint: browser.themeColor)
                } else {
                    Mark(icon: prefs.glyph == .icons ? tab.icon : nil, letter: tab.monogram, size: 15, dim: tab.asleep, tint: browser.themeColor)
                }
            }
            .frame(width: 16, height: 16)
            .padding(.vertical, 7)
            .frame(width: span)
        } else {
            titled
        }
    }

    private var titled: some View {
        HStack(spacing: 6) {
            if hovering || (prefs.glyph == .icons && !tab.isBlank) {
                // The close lives where the mark was: the face swaps for
                // a cross under the hand, and the tap swaps with it.
                ZStack {
                    if hovering {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(muted)
                            .frame(width: 15, height: 15)
                            .background(closePlate, in: Circle())
                            .transition(.opacity)
                    } else if prefs.glyph == .icons, !tab.isBlank {
                        Mark(icon: tab.icon, letter: tab.monogram, size: 15, tint: browser.themeColor)
                    }
                }
                .frame(width: 15, height: 15)
                .overlay {
                    if hovering {
                        Color.clear
                            .frame(width: 24, height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                    }
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

            HStack(spacing: 4) {
                // Video pop-out, left of reload: the same Shift-Cmd-P path as
                // Float Video. The live-plus-hover gate stays, and on top of
                // it the icon only appears while floating would actually work
                // (`canFloat`) or already is (`floating`, as the way back) —
                // so tabs without a playing video never grow it on hover.
                if live && (hovering || tab.floating) && (tab.floating || tab.canFloat) {
                    Button { browser.toggleFloat() } label: {
                        Image(systemName: tab.floating ? "pip.exit" : "pip.enter")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(muted)
                            .frame(width: 15, height: 15)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(tab.isBlank && !tab.floating)
                    .opacity(tab.isBlank && !tab.floating ? 0.3 : 1)
                    .help("Float Video   ⇧⌘P")
                    .accessibilityLabel("Float Video")
                    .transition(.opacity)
                }
                // Hover reload inside the live pill: a stop while the page
                // is still on its way, a reload otherwise. Trailing,
                // alongside the speaker — the close up front is untouched.
                if live && hovering {
                    Button {
                        if tab.loading { tab.stop() } else { tab.reload() }
                    } label: {
                        Group {
                            if tab.loading {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .semibold))
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                        }
                        .foregroundStyle(muted)
                        .frame(width: 15, height: 15)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(tab.isBlank && !tab.loading)
                    .opacity(tab.isBlank && !tab.loading ? 0.3 : 1)
                    .help(tab.loading ? "Stop   ⌘." : "Reload   ⌘R")
                    .accessibilityLabel(tab.loading ? "Stop" : "Reload")
                    .transition(.opacity)
                }
                // Which tab the noise is coming from. ⌘⇧M stops it.
                if tab.noisy {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(muted)
                        .frame(width: 15, height: 15)
                }
            }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: tab.loading)
            .animation(Motion.quick, value: tab.canFloat)
            .animation(Motion.quick, value: tab.floating)
        }
        // Reserve the row height a titled tab always needs, so a blank tab
        // hovering from empty to "New Tab" changes only paint, never size:
        // without this the idle HStack is just a Spacer and the pill grows
        // taller on hover, which reads as it jumping up off the baseline.
        .frame(minHeight: 16)
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .frame(width: span, alignment: .leading)
    }

    @ViewBuilder
    private var ground: some View {
        if live {
            // The grey fills from the left as you read down the page. It is
            // the one thing in the window that says how far in you are, and
            // it says it without adding anything to the window. On a tint
            // the pill is the on-tint foreground laid over the bar, so the
            // full-strength on-tint text sits on a ground of its own family
            // instead of white on fixed light grey.
            if browser.insertedID == tab.id {
                // Just inserted by `+`: no slide. The matched pill gliding
                // here while the new pill's own appear transition runs is
                // the duplicated/offset ghost. A plain ground arrives with
                // the pill itself; the matched pill takes over once settled
                // (same frame, so the handover is invisible).
                ZStack(alignment: .leading) {
                    Rectangle().fill(liveGround)
                    if !pinned && !compact {
                        Rectangle()
                            .fill(progressGround)
                            .frame(width: span * tab.reading)
                            .animation(.easeOut(duration: 0.15), value: tab.reading)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                ZStack(alignment: .leading) {
                    Rectangle().fill(liveGround)
                    // Not on a pinned square, nor a tab down to its mark. Thirty
                    // points of grey filling from the left behind a single letter
                    // says nothing about anything — it needs the width of a title
                    // to read as progress at all.
                    if !pinned && !compact {
                        Rectangle()
                            .fill(progressGround)
                            .frame(width: span * tab.reading)
                            .animation(.easeOut(duration: 0.15), value: tab.reading)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .matchedGeometryEffect(id: "live", in: pill)
            }
        } else if hovering {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hoverGround)
        } else if pinned {
            // A letter with nothing behind it reads as debris. A pinned tab
            // keeps a faint ground of its own so the block of them reads as
            // one thing.
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(pinGround)
        }
    }

    /// Opaque bar behind this pill; nil keeps every existing Palette ground.
    private var tint: Tint? { browser.themeColor }
    private var onTint: Color { Palette.foreground(on: tint) }
    private var liveGround: Color {
        guard tint != nil else { return Palette.wash }
        return onTint.opacity(0.22)
    }
    private var hoverGround: Color {
        guard tint != nil else { return Palette.hover }
        return onTint.opacity(0.12)
    }
    private var pinGround: Color {
        guard tint != nil else { return Palette.wash.opacity(0.55) }
        return onTint.opacity(0.08)
    }
    private var progressGround: Color {
        guard tint != nil else { return Palette.ink.opacity(0.055) }
        return onTint.opacity(0.14)
    }
    private var closePlate: Color {
        guard tint != nil else { return Palette.ink.opacity(0.07) }
        return onTint.opacity(0.16)
    }


    private var colour: Color {
        if live { return ink }
        return hovering ? ink.opacity(0.7) : muted
    }

    private var ink: Color { Palette.foreground(on: browser.themeColor) }
    private var muted: Color { Palette.foreground(on: browser.themeColor, dimmed: true) }
}

/// The address in a tab, the letter on a pin: one AppKit field for the two
/// places SwiftUI's selection paint is too loud — the system fills selected
/// text with accent colour, over a pale pill or a thirty-point square the
/// loudest thing on screen. Here it is a tenth of the ink. Same field,
/// different wiring.
struct PillField: NSViewRepresentable {
    @ObservedObject var browser: Browser
    /// Website tint behind the tab. Nil keeps the existing ink.
    var tint: Tint? = nil
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
        if let tint {
            field.textColor = NSColor(Palette.foreground(on: tint))
        } else {
            field.textColor = Palette.NS.ink
        }
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
        if let tint {
            field.textColor = NSColor(Palette.foreground(on: tint))
        } else {
            field.textColor = Palette.NS.ink
        }
        guard !coordinator.claimed else {
            if let editor = field.currentEditor() as? NSTextView {
                if let tint {
                    let fg = Palette.foreground(on: tint)
                    editor.selectedTextAttributes = [
                        .backgroundColor: NSColor(fg.opacity(0.22)),
                        .foregroundColor: NSColor(fg),
                    ]
                }
            }
            return
        }
        coordinator.claimed = true
        let captured = tint
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            guard let editor = field.currentEditor() as? NSTextView else { return }
            if let captured {
                let fg = Palette.foreground(on: captured)
                editor.selectedTextAttributes = [
                    .backgroundColor: NSColor(fg.opacity(0.22)),
                    .foregroundColor: NSColor(fg),
                ]
            } else {
                editor.selectedTextAttributes = [
                    .backgroundColor: NSColor(Palette.ink.opacity(0.11)),
                    .foregroundColor: Palette.NS.ink,
                ]
            }
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
        Menu("Tab Color") {
            ForEach(tab.palette, id: \.hex) { tint in
                Button {
                    tab.choose(tint)
                } label: {
                    Label { Text(tab.chosenTint == tint ? "\(tint.hex)  ✓" : tint.hex) } icon: { Image(nsImage: tint.swatch) }
                }
            }
            if !tab.palette.isEmpty { Divider() }
            Button("The Page's Own") { tab.choose(nil) }
                .disabled(tab.chosenTint == nil)
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
    /// Website tint behind the tab. Nil keeps the existing grey.
    var tint: Tint? = nil
    @State private var angle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.78)
            .stroke(
                (tint != nil ? Palette.foreground(on: tint) : Palette.muted).opacity(0.7),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
