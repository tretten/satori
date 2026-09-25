import SwiftUI

/// The tabs, down the left instead of across the top.
///
/// The same pieces as the strip — the grey that slides to the tab you picked,
/// the pinned squares, the cross that appears under the pointer — laid out the
/// other way. The traffic lights keep their corner; the column starts under
/// them and the page takes the whole height beside it.
struct SideBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @Namespace private var pill

    @State private var dragging: Tab.ID?
    @State private var from = 0
    @State private var travel: CGFloat = 0
    @State private var landing = false
    /// The width the column had when the edge was picked up.
    @State private var grabbed: CGFloat?
    @State private var onEdge = false

    /// A pin, picked up out of the grid — a separate state from the loose
    /// rows above, since the two gestures never happen at once but move on
    /// two different axes.
    @State private var pinDragging: Tab.ID?
    @State private var pinFrom = 0
    @State private var pinTravel: CGSize = .zero
    @State private var hoveringNew = false

    private static let row: CGFloat = 28
    private static let gap: CGFloat = 2
    private static let square: CGFloat = 34
    private static let pinGap: CGFloat = 4

    var body: some View {
        ZStack(alignment: .top) {
            DragStrip(reserved: 0, below: rowsEnd)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The band the lights sit in is this mode's title bar: the window
            // is dragged by it and a double-click fills the screen with it,
            // everywhere but over the two doors, which take their own
            // clicks. The lights are the title bar's own and answer first.
            HStack(spacing: 0) {
                DragStrip()
                    .frame(width: 10 + Metrics.sideLights, height: Metrics.strip)
                Color.clear
                    .frame(width: Metrics.helm)
                    .allowsHitTesting(false)
                DragStrip()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: Metrics.strip)

            VStack(alignment: .leading, spacing: 0) {
                // The traffic lights' corner, with back and forward
                // sitting right of them — the same two doors as the top
                // bar, moved beside the lights since there's no far end of a
                // row to put them at in this mode.
                HStack(spacing: 0) {
                    Color.clear.frame(width: Metrics.sideLights)
                    Helm(browser: browser)
                    Spacer(minLength: 0)
                }
                .frame(height: Metrics.strip)

                if browser.pinnedCount > 0 {
                    pinned
                        .padding(.bottom, 10)
                }

                loose
                newTab

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)

            VStack {
                Spacer()
                foot
            }
        }
        .frame(width: prefs.sideWidth)
        .frame(maxHeight: .infinity)
        .background(landing ? Palette.hover : Palette.ground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.hairline).frame(width: 1)
        }
        .overlay(alignment: .trailing) { edge }
        .onDrop(of: [.url, .text], isTargeted: $landing) { providers in
            browser.take(providers)
        }
        .animation(Motion.quick, value: landing)
        // Same as the top strip: the transaction that activates a
        // just-inserted tab must not slide the live pill, or the ghost
        // doubles the new row while it transitions in.
        .animation(browser.insertedID == nil ? Motion.settle : nil, value: browser.activeID)
        // No animation on tab-list identity: same freeze as the top strip —
        // every insertion animated all rows at once. Reorder animates explicitly.
        .animation(Motion.settle, value: browser.pinnedCount)
    }

    /// The column's edge: pull it to make the column wider or narrower,
    /// double-click it to put it back. The hairline darkens under the pointer
    /// so the edge says it can be taken before it is.
    private var edge: some View {
        Rectangle()
            .fill(Palette.ink.opacity(onEdge || grabbed != nil ? 0.18 : 0))
            .frame(width: onEdge || grabbed != nil ? 2 : 1)
            .frame(width: 9)
            .contentShape(Rectangle())
            .onHover { over in
                onEdge = over
                if over { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if grabbed == nil { grabbed = prefs.sideWidth }
                        let wanted = (grabbed ?? prefs.sideWidth) + value.translation.width
                        prefs.sideWidth = min(Metrics.sideMax, max(Metrics.sideMin, wanted))
                    }
                    .onEnded { _ in grabbed = nil }
            )
            .modifier(OneClick(double: true) {
                withAnimation(Motion.settle) { prefs.sideWidth = Metrics.side }
            })
            .animation(Motion.quick, value: onEdge)
    }

    /// Where the rows stop and the window's own drag area starts. Added up
    /// from what was drawn rather than measured: a measurement would arrive a
    /// frame late, and for one frame the whole column would drag the window.
    private var rowsEnd: CGFloat {
        let pins = browser.pinnedCount
        let cols = SideBar.pinColumns(pins)
        let pinRows = pins == 0 ? 0 : (pins + cols - 1) / cols
        let pinBlock = pinRows == 0 ? 0
            : CGFloat(pinRows) * pinHeight + CGFloat(pinRows - 1) * SideBar.pinGap + 10
        let loose = CGFloat(browser.tabs.count - pins) * (SideBar.row + SideBar.gap)
        return Metrics.strip + pinBlock + loose + SideBar.row + 8
    }

    // MARK: - the pinned squares

    private var pinnedTabs: [Tab] { browser.tabs.filter { $0.pin != nil } }
    private var looseTabs: [Tab] { browser.tabs.filter { $0.pin == nil } }

    /// Three columns is the block's own shape — up to six pins, that's two
    /// full rows, and one or two is just those same three places with a
    /// couple of them empty rather than a lonely row of its own width. Only
    /// past six does the block widen, one column at a time, to stay at two
    /// rows for as long as that's a reasonable shape at all.
    private static func pinColumns(_ count: Int) -> Int {
        max(3, (count + 1) / 2)
    }

    /// However many columns the count calls for, they split the row's own
    /// width between them — the row is what fills edge to edge, not each
    /// cell on its own, so this grows past 34 just as readily as it shrinks
    /// below it.
    private var pinWidth: CGFloat {
        let cols = SideBar.pinColumns(browser.pinnedCount)
        guard cols > 0 else { return SideBar.square }
        let available = prefs.sideWidth - 20 - CGFloat(cols - 1) * SideBar.pinGap
        return max(20, available / CGFloat(cols))
    }

    /// The one dimension that doesn't chase the sidebar's width: past three
    /// columns' worth of room a cell would otherwise turn into a big square
    /// rather than the wide, short button pinned tabs actually look like
    /// everywhere else in this app. It only shrinks below 34 alongside the
    /// width, once a narrow column leaves no other choice.
    private var pinHeight: CGFloat {
        min(SideBar.square, pinWidth)
    }

    /// The grid itself: fixed-size cells, left-aligned, so a half-empty last
    /// row holds its ground rather than stretching to fill it.
    private var pinned: some View {
        let tabs = pinnedTabs
        let cols = SideBar.pinColumns(tabs.count)
        let width = pinWidth
        let height = pinHeight
        let columns = Array(repeating: GridItem(.fixed(width), spacing: SideBar.pinGap), count: cols)
        // Measured in the grid's own space, not the square's: a square that
        // has just been moved to a new cell would otherwise report the drag
        // from where it now is, the target would jump back, and the square
        // would shuttle between two cells for as long as the finger stayed.
        return VStack(spacing: 0) { LazyVGrid(columns: columns, alignment: .leading, spacing: SideBar.pinGap) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                let held = pinDragging == tab.id
                PinSquare(
                    browser: browser,
                    prefs: prefs,
                    tab: tab,
                    live: tab.id == browser.activeID,
                    pill: pill,
                    width: width,
                    height: height
                )
                .offset(pinOffset(held: held, index: index, columns: cols))
                .zIndex(held ? 1 : 0)
                .shadow(color: .black.opacity(held ? 0.16 : 0), radius: 10, y: 3)
                .highPriorityGesture(pinReorder(tab: tab, index: index, columns: cols, width: width, height: height))
            }
        } }
        .coordinateSpace(name: "pins")
    }

    /// The one square actually held stays glued to the fingers; every other
    /// square is already exactly where it belongs, because `browser.move`
    /// put it there — this only cancels out the bit of that same movement
    /// the held square already got for free by changing index underneath
    /// its own drag.
    private func pinOffset(held: Bool, index: Int, columns: Int) -> CGSize {
        guard held else { return .zero }
        let stepX = pinWidth + SideBar.pinGap
        let stepY = pinHeight + SideBar.pinGap
        let from = (row: pinFrom / columns, col: pinFrom % columns)
        let now = (row: index / columns, col: index % columns)
        return CGSize(
            width: pinTravel.width - CGFloat(now.col - from.col) * stepX,
            height: pinTravel.height - CGFloat(now.row - from.row) * stepY
        )
    }

    /// How many cells the drag has moved, in the grid's own row-major order
    /// — a straight line through the array a column-major offset would get
    /// wrong the moment it crossed a row. Row and column travel each measure
    /// themselves against that axis's own step now that a cell's width and
    /// height aren't the same number.
    private func pinDelta(columns: Int, stepX: CGFloat, stepY: CGFloat) -> Int {
        let col = Int((pinTravel.width / stepX).rounded())
        let row = Int((pinTravel.height / stepY).rounded())
        return row * columns + col
    }

    private func pinTarget(from: Int, moved: Int) -> Int {
        min(max(0, from + moved), max(0, pinnedTabs.count - 1))
    }

    /// Pick a square up and the others make way — across a row, and down
    /// into the next, exactly as far as the fingers actually moved.
    private func pinReorder(tab: Tab, index: Int, columns: Int, width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("pins"))
            .onChanged { value in
                if pinDragging != tab.id {
                    pinDragging = tab.id
                    pinFrom = index
                }
                pinTravel = value.translation
                let stepX = width + SideBar.pinGap
                let stepY = height + SideBar.pinGap
                let target = pinTarget(from: pinFrom, moved: pinDelta(columns: columns, stepX: stepX, stepY: stepY))
                if target != index {
                    withAnimation(Motion.settle) {
                        browser.move(tab, to: target)
                    }
                }
            }
            .onEnded { _ in
                withAnimation(Motion.settle) {
                    pinDragging = nil
                    pinTravel = .zero
                }
            }
    }

    // MARK: - the rows

    private var loose: some View {
        VStack(spacing: SideBar.gap) {
            // See the grid: the drag is measured in the column's space, not
            // the row's, so a row that has just moved keeps its bearings.
            ForEach(Array(looseTabs.enumerated()), id: \.element.id) { index, tab in
                let step = SideBar.row + SideBar.gap
                let held = dragging == tab.id
                SideRow(
                    browser: browser,
                    prefs: prefs,
                    tab: tab,
                    live: tab.id == browser.activeID,
                    pill: pill,
                    close: { browser.close(tab) }
                )
                .offset(y: held ? travel - CGFloat(index - from) * step : 0)
                .zIndex(held ? 1 : 0)
                .shadow(color: .black.opacity(held ? 0.14 : 0), radius: 12, y: 4)
                .highPriorityGesture(reorder(tab: tab, index: index, step: step))
            }
        }
        .coordinateSpace(name: "rows")
    }

    /// Pick a row up and the others make way as it passes them.
    private func reorder(tab: Tab, index: Int, step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("rows"))
            .onChanged { value in
                if dragging != tab.id {
                    dragging = tab.id
                    from = index
                }
                travel = value.translation.height
                let moved = Int((travel / step).rounded())
                let target = min(max(0, from + moved), looseTabs.count - 1)
                if target != index {
                    // Positions here are among the loose rows; the pinned
                    // block sits in front of them in the real list.
                    withAnimation(Motion.settle) {
                        browser.move(tab, to: target + browser.pinnedCount)
                    }
                }
            }
            .onEnded { _ in
                withAnimation(Motion.settle) {
                    dragging = nil
                    travel = 0
                }
            }
    }

    private var newTab: some View {
        Button(action: { browser.newTab() }) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 15)
                Text("New tab")
                    .font(.system(size: 12.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(hoveringNew ? Palette.ink.opacity(0.7) : Palette.faint)
            .padding(.leading, 10)
            .frame(height: SideBar.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hoveringNew ? Palette.hover : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveringNew = $0 }
        .animation(Motion.quick, value: hoveringNew)
        .padding(.top, SideBar.gap)
    }

    /// Small doors at the bottom: the bookmarks, the settings.
    private var foot: some View {
        HStack(spacing: 2) {
            ExtensionSlot(edge: .trailing)
                // Same as the top strip: icons stay out of the insertion transaction.
                .transaction { $0.animation = nil }
            if !browser.downloading.isEmpty || !browser.loot.kept.isEmpty {
                Door(
                    icon: browser.downloading.isEmpty ? "arrow.down.circle" : "arrow.down.circle.fill",
                    help: "Downloads   ⇧⌘J"
                ) { browser.hoarding.toggle() }
            }
            Door(icon: "command", help: "Settings   ⌘,") { browser.tuning.toggle() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

}

/// A pinned tab as a cell in the block at the top of the column — as wide as
/// its row asks for, but never taller than the classic square, so a row with
/// room to spare turns into a wide, short button rather than a bigger icon.
private struct PinSquare: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let pill: Namespace.ID
    var width: CGFloat = 34
    var height: CGFloat = 34

    @State private var hovering = false
    /// See the tab pills: one tap only, so picking never waits out the
    /// system's double-click delay; a second tap soon after counts as the
    /// double-click that edits the pin's letter.
    @State private var lastTap = Date.distantPast

    /// Everything drawn inside scales off the shorter edge — the one that
    /// stays put — so the glyph sits at its usual size, centred, rather than
    /// stretching to chase the width.
    private var scale: CGFloat { min(width, height) }

    var body: some View {
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
                Mark(icon: icon, letter: tab.pin ?? "", size: scale * 16 / 34, dim: tab.asleep)
            } else {
                Text(tab.pin ?? "")
                    .font(.system(size: scale * 12 / 34, weight: .medium))
                    .foregroundStyle((live ? Palette.ink : Palette.muted).opacity(tab.asleep ? 0.45 : 1))
            }
        }
        .frame(width: scale * 16 / 34, height: scale * 16 / 34)
        .frame(width: width, height: height)
        .background {
            if live {
                if browser.insertedID == tab.id {
                    // Just inserted: arrive with the cell, don't slide.
                    RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous)
                        .fill(Palette.wash)
                } else {
                    RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous)
                        .fill(Palette.wash)
                        .matchedGeometryEffect(id: "live", in: pill)
                }
            } else {
                RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous)
                    .fill(hovering ? Palette.hover : Palette.wash.opacity(0.55))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: scale * 9 / 34, style: .continuous))
        .onTapGesture {
            let now = Date()
            let double = now.timeIntervalSince(lastTap) < 0.4
            lastTap = now
            if double {
                if tab.id != browser.activeID { browser.select(tab) }
                browser.editLetter(tab)
                return
            }
            if live {
                tab.scrollToTop()
            } else {
                browser.select(tab)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { TabMenu(browser: browser, tab: tab, close: { browser.close(tab) }) }
        .help(tab.label)
        .accessibilityHint(live ? "Scrolls to the top. Double-click changes the letter." : "Shows this tab. Double-click changes its letter.")
        .animation(Motion.quick, value: hovering)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// One tab, as a line in the column.
private struct SideRow: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject var tab: Tab
    let live: Bool
    let pill: Namespace.ID
    let close: () -> Void

    @State private var hovering = false
    /// See the tab pills: one tap only, so picking never waits out the
    /// system's double-click delay; a second tap soon after counts as the
    /// double-click that raises the centred address field.
    @State private var lastTap = Date.distantPast

    var body: some View {
        HStack(spacing: 8) {
            if hovering || (prefs.glyph == .icons && !tab.isBlank) {
                // The close lives where the mark was: the face swaps for
                // a cross under the hand, and the tap swaps with it.
                ZStack {
                    if hovering {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 15, height: 15)
                            .background(Palette.ink.opacity(0.07), in: Circle())
                            .transition(.opacity)
                    } else if prefs.glyph == .icons, !tab.isBlank {
                        Mark(icon: tab.icon, letter: tab.monogram, size: 15)
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

            // Reload at the row's far end: the ring while the page is still
            // coming (a tap stops it), the arrow otherwise — always on the
            // tab you are on, under the hand on the rest.
            ZStack {
                if tab.loading {
                    if hovering {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 15, height: 15)
                            .transition(.opacity)
                            .help("Stop   ⌘.")
                    } else {
                        Ring().transition(.opacity)
                    }
                } else if hovering || live {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 15, height: 15)
                        .transition(.opacity)
                        .help("Reload   ⌘R")
                } else if tab.noisy {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Palette.muted)
                        .transition(.opacity)
                }
            }
            .frame(width: 15, height: 15)
            .overlay {
                Color.clear
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if tab.loading { tab.stop() }
                        else if hovering || live { tab.reload() }
                    }
            }
            .animation(Motion.quick, value: hovering)
            .animation(Motion.quick, value: tab.loading)
            .animation(Motion.quick, value: tab.noisy)
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ground }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        // One tap gesture only, so picking a row never waits out the system's
        // double-click delay (see `lastTap`). A single click on the row already
        // showing scrolls its page to the top; a double-click raises the
        // centred address field, picking the row first when left alone.
        .onTapGesture {
            let now = Date()
            let double = now.timeIntervalSince(lastTap) < 0.4
            lastTap = now
            if double {
                if tab.id != browser.activeID { browser.select(tab) }
                browser.edit()
                return
            }
            if live {
                tab.scrollToTop()
            } else {
                browser.select(tab)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu { TabMenu(browser: browser, tab: tab, close: close) }
        .accessibilityHint(live ? "Scrolls to the top. Double-click opens the address field." : "Shows this tab. Double-click opens its address field.")
        .animation(Motion.quick, value: hovering)
        .transition(.scale(scale: 0.94, anchor: .leading).combined(with: .opacity))
    }

    @ViewBuilder
    private var ground: some View {
        if live {
            if browser.insertedID == tab.id {
                // Just inserted by `+`: a plain ground arrives with the row
                // instead of sliding the old pill across it (the ghost).
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.wash)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Palette.ink.opacity(0.055))
                            .frame(width: geo.size.width * tab.reading)
                            .animation(.easeOut(duration: 0.15), value: tab.reading)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.wash)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Palette.ink.opacity(0.055))
                            .frame(width: geo.size.width * tab.reading)
                            .animation(.easeOut(duration: 0.15), value: tab.reading)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .matchedGeometryEffect(id: "live", in: pill)
            }
        } else if hovering {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Palette.hover)
        }
    }

    private var colour: Color {
        if live { return Palette.ink }
        return hovering ? Palette.ink.opacity(0.7) : Palette.muted
    }
}

/// A small square holding one symbol. Lit when what it opens is open.
struct Door: View {
    let icon: String
    var on = false
    var help = ""
    /// Website tint behind the top bar. Nil keeps the existing Palette
    /// grounds/inks, so the sidebar and every other use stay unchanged.
    var tint: Tint? = nil
    let act: () -> Void

    @State private var hovering = false

    private var ink: Color { Palette.foreground(on: tint) }
    private var muted: Color { Palette.foreground(on: tint, dimmed: true) }
    private var lit: Color {
        guard let tint else { return Palette.wash }
        return Palette.foreground(on: tint).opacity(0.22)
    }
    private var hovered: Color {
        guard let tint else { return Palette.hover }
        return Palette.foreground(on: tint).opacity(0.12)
    }

    var body: some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? ink : (hovering ? ink.opacity(0.7) : muted))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(on ? lit : (hovering ? hovered : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(Pressable())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: on)
    }
}
