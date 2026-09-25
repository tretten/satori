import AppKit
import WebKit

// A video that keeps playing after you have gone somewhere else, in a small
// window that stays above everything — other tabs, and other apps.
//
// WebKit will not hand a video to the system's picture-in-picture without a
// real click on the page, and nothing the app does counts as one. Chromium is
// looser, which is why this works elsewhere and refused here.
//
// So the engine is not asked. The page itself is moved: everything but the
// video is made invisible, the video is stretched to fill the viewport, and the
// whole web view is lifted out of the window and into a small floating one. The
// video never stops, because it is the same page it always was — it has only
// changed windows.

@MainActor
final class Float {
    private var panel: NSPanel?
    private var controls: Controls?
    private weak var page: NSView?

    /// Asked to go away. The browser does the bookkeeping and calls back into
    /// `drop` — there is one way this window closes, and it is not this class
    /// quietly tidying up behind everyone's back. Two paths to closing is how
    /// it stayed on screen after the page had already gone home.
    var onClose: (() -> Void)?
    /// Bring the window forward and go to the tab it came from.
    var onReturn: (() -> Void)?
    /// Stop or start the video. Answers with whether it is playing now.
    var onPlayPause: ((@escaping (Bool) -> Void) -> Void)?
    /// Step over the bit you missed, or back to it.
    var onSkip: ((Double) -> Void)?
    /// Asked every half second while the window is up, for the line along the
    /// bottom edge.
    var onProgress: ((@escaping (Double, Bool) -> Void) -> Void)?

    private var ticker: Timer?

    var showing: Bool { panel != nil }

    func lift(_ page: NSView) {
        guard panel == nil else { return }
        self.page = page

        let size = NSSize(width: 440, height: 247)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let spot = NSRect(
            x: screen.maxX - size.width - 24,
            y: screen.minY + 24,
            width: size.width,
            height: size.height
        )

        let panel = Panel(
            contentRect: spot,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above every ordinary window, this app's and everyone else's, and
        // present on whichever desktop you happen to be looking at.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.aspectRatio = size
        panel.minSize = NSSize(width: 260, height: 146)

        let ground = NSView(frame: NSRect(origin: .zero, size: size))
        ground.wantsLayer = true
        ground.layer?.backgroundColor = NSColor.black.cgColor
        ground.layer?.cornerRadius = 14
        ground.layer?.masksToBounds = true

        // WebKit puts its own pinch recogniser on a web view, and a gesture
        // recogniser is consulted before the responder chain is. With it left
        // on, every pinch aimed at this window went into zooming the page
        // inside it instead of sizing the window. It comes back on landing.
        (page as? WKWebView)?.allowsMagnification = false

        page.removeFromSuperview()
        page.frame = ground.bounds
        page.autoresizingMask = [.width, .height]
        ground.addSubview(page)
        // Any obscured top inset lives on the WKWebView itself
        // (`_setTopContentInset:` → obscuredContentInsets), so it travels with
        // the page and would offset the fixed video in this chromeless window
        // — a black band across the top. Clearing once here removes it. The
        // stage skips floating pages from here on and restores the strip value
        // (48) on landing.
        StageView.applyTopInset(0, to: page)

        let controls = Controls(frame: ground.bounds)
        controls.autoresizingMask = [.width, .height]
        controls.onClose = { [weak self] in self?.onClose?() }
        controls.onReturn = { [weak self] in self?.onReturn?() }
        controls.onPlayPause = { [weak self] in
            self?.onPlayPause? { playing in
                self?.controls?.playing = playing
            }
        }
        controls.onSkip = { [weak self] seconds in self?.onSkip?(seconds) }
        ground.addSubview(controls)
        self.controls = controls

        panel.contentView = ground
        panel.orderFrontRegardless()
        self.panel = panel

        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }

                // A window that no longer holds the page has nothing to show
                // and no reason to exist. Something else took the page back —
                // and rather than hunt every path that could, this makes it
                // impossible for the empty black rectangle to outlive it by
                // more than half a second.
                if self.page?.superview !== ground {
                    self.onClose?()
                    return
                }

                self.onProgress? { through, playing in
                    self.controls?.progress = through
                    self.controls?.playing = playing
                }
            }
        }
    }

    /// Puts the page down and closes. Whoever owns the page takes it back on
    /// their next layout.
    func drop() {
        guard let panel else { return }
        ticker?.invalidate()
        ticker = nil
        (page as? WKWebView)?.allowsMagnification = true
        page?.removeFromSuperview()
        page = nil
        controls = nil
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }

    /// What a small window of video needs, and nothing else: a way out, a way
    /// back, a way to stop it, and a way to step over the bit you missed.
    ///
    /// Out of sight until the pointer is over the window — the whole point of
    /// this window is the picture.
    private final class Controls: NSView {
        var onClose: (() -> Void)?
        var onReturn: (() -> Void)?
        var onPlayPause: (() -> Void)?
        var onSkip: ((Double) -> Void)?

        var playing = true {
            didSet { pause.image = glyph(playing ? "pause.fill" : "play.fill", 17) }
        }

        /// Nought to one. Drawn as a hairline along the bottom edge.
        var progress: Double = 0 {
            didSet { line.through = progress }
        }

        private let close = NSButton()
        private let back = NSButton()
        private let pause = NSButton()
        private let rewind = NSButton()
        private let forward = NSButton()
        private let scrim = CAGradientLayer()
        private let line = Line()
        private var near = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true

            // A wash at the top and bottom, so white buttons hold against a
            // bright frame of film without covering it.
            scrim.colors = [
                NSColor(white: 0, alpha: 0.45).cgColor,
                NSColor(white: 0, alpha: 0).cgColor,
                NSColor(white: 0, alpha: 0).cgColor,
                NSColor(white: 0, alpha: 0.5).cgColor,
            ]
            scrim.locations = [0, 0.28, 0.66, 1]
            scrim.opacity = 0
            layer?.addSublayer(scrim)

            dress(close, "xmark", 11, round: 15, action: #selector(pressedClose))
            dress(back, "arrow.up.forward", 12, round: 15, action: #selector(pressedReturn))
            dress(rewind, "gobackward.15", 15, round: 19, action: #selector(pressedRewind))
            dress(pause, "pause.fill", 17, round: 25, action: #selector(pressedPause))
            dress(forward, "goforward.15", 15, round: 19, action: #selector(pressedForward))

            line.alphaValue = 0
            addSubview(line)
            buttons.forEach { $0.alphaValue = 0 }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        private var buttons: [NSButton] { [close, back, rewind, pause, forward] }

        private func dress(
            _ button: NSButton,
            _ symbol: String,
            _ size: CGFloat,
            round: CGFloat,
            action: Selector
        ) {
            button.image = glyph(symbol, size)
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.target = self
            button.action = action
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.55).cgColor
            button.layer?.cornerRadius = round
            addSubview(button)
        }

        private func glyph(_ name: String, _ size: CGFloat) -> NSImage? {
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            let look = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
                .applying(.init(paletteColors: [.white]))
            return image?.withSymbolConfiguration(look)
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            scrim.frame = bounds
            CATransaction.commit()

            close.frame = NSRect(x: 14, y: bounds.height - 44, width: 30, height: 30)
            back.frame = NSRect(x: bounds.width - 44, y: bounds.height - 44, width: 30, height: 30)

            let middle = bounds.midY - 25
            pause.frame = NSRect(x: bounds.midX - 25, y: middle, width: 50, height: 50)
            rewind.frame = NSRect(x: bounds.midX - 25 - 54, y: middle + 6, width: 38, height: 38)
            forward.frame = NSRect(x: bounds.midX + 25 + 16, y: middle + 6, width: 38, height: 38)

            line.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 3)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self
                )
            )
        }

        override func mouseEntered(with event: NSEvent) { fade(to: 1) }
        override func mouseExited(with event: NSEvent) { fade(to: 0) }

        private func fade(to value: CGFloat) {
            near = value > 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                buttons.forEach { $0.animator().alphaValue = value }
                line.animator().alphaValue = value
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.16)
            scrim.opacity = Swift.Float(value)
            CATransaction.commit()
        }

        /// Everything reaches this layer.
        ///
        /// isMovableByWindowBackground never worked here: the window's whole
        /// background is a web view, and a web view swallows every drag before
        /// the window sees it. So every gesture is taken here, above it.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let inside = convert(point, from: superview)
            if near {
                for button in buttons where button.frame.contains(inside) {
                    return button
                }
            }
            return self
        }

        // MARK: - moving and sizing

        private var grab = NSPoint.zero
        private var origin = NSRect.zero
        private var stretching = false

        private func atCorner(_ point: NSPoint) -> Bool {
            point.x > bounds.maxX - 22 && point.y < bounds.minY + 22
        }

        override func resetCursorRects() {
            addCursorRect(
                NSRect(x: bounds.maxX - 22, y: bounds.minY, width: 22, height: 22),
                cursor: .crosshair
            )
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            // Caught mid-flight: it stops where it is, under the hand.
            land()
            grab = NSEvent.mouseLocation
            origin = window.frame
            stretching = atCorner(convert(event.locationInWindow, from: nil))
            moved = false
            speed = .zero
            last = (grab, event.timestamp)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            let dx = now.x - grab.x
            let dy = now.y - grab.y
            moved = true

            // Smoothed, so one jittery event at the end can't decide the throw.
            let dt = event.timestamp - last.at
            if dt > 0 {
                let vx = (now.x - last.spot.x) / dt
                let vy = (now.y - last.spot.y) / dt
                speed = CGVector(dx: speed.dx * 0.3 + vx * 0.7, dy: speed.dy * 0.3 + vy * 0.7)
            }
            last = (now, event.timestamp)

            guard stretching else {
                window.setFrameOrigin(NSPoint(x: origin.minX + dx, y: origin.minY + dy))
                return
            }
            resize(to: origin.width + dx, from: origin)
        }

        override func mouseUp(with event: NSEvent) {
            guard moved, !stretching, let window else { return }
            // A hand that stopped before letting go threw nothing.
            if event.timestamp - last.at > 0.05 { speed = .zero }
            fling(window)
        }

        // MARK: - going to a corner

        private var moved = false
        private var speed = CGVector.zero
        private var last: (spot: NSPoint, at: TimeInterval) = (.zero, 0)
        private var flight: Timer?

        /// Where a throw would come to rest, the way a scroll glides out
        /// (Apple's projection, deceleration 0.998), then the nearest corner
        /// of the screen to that — not to where the hand let go. A flick
        /// crosses the screen; a gentle drop stays near.
        private func fling(_ window: NSWindow) {
            let frame = window.frame
            let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? frame
            func project(_ v: CGFloat) -> CGFloat { v / 1000 * 0.998 / (1 - 0.998) }
            let ahead = NSPoint(x: frame.midX + project(speed.dx), y: frame.midY + project(speed.dy))

            let margin: CGFloat = 24
            let left = screen.minX + margin
            let right = screen.maxX - frame.width - margin
            let bottom = screen.minY + margin
            let top = screen.maxY - frame.height - margin
            let to = NSPoint(
                x: ahead.x < screen.midX ? left : right,
                y: ahead.y < screen.midY ? bottom : top
            )

            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                window.setFrameOrigin(to)
                return
            }
            glide(window, to: to, velocity: speed)
        }

        /// A critically damped spring, response 0.4 s — what Apple's own
        /// picture-in-picture moves with. It leaves at the speed the hand let
        /// go with, so there is no seam between dragging and gliding, and it
        /// settles without overshoot.
        private func glide(_ window: NSWindow, to: NSPoint, velocity: CGVector) {
            let from = window.frame.origin
            let omega = 2 * CGFloat.pi / 0.4
            let begun = CACurrentMediaTime()
            func axis(_ x0: CGFloat, _ v0: CGFloat, _ t: CGFloat) -> CGFloat {
                (x0 + (v0 + omega * x0) * t) * exp(-omega * t)
            }
            flight = Timer.scheduledTimer(withTimeInterval: 1 / 120, repeats: true) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return self?.land() ?? () }
                    let t = CGFloat(CACurrentMediaTime() - begun)
                    let x = axis(from.x - to.x, velocity.dx, t)
                    let y = axis(from.y - to.y, velocity.dy, t)
                    if t > 1.2 || (abs(x) < 0.5 && abs(y) < 0.5 && t > 0.1) {
                        window.setFrameOrigin(to)
                        self.land()
                        return
                    }
                    window.setFrameOrigin(NSPoint(x: to.x + x, y: to.y + y))
                }
            }
        }

        private func land() {
            flight?.invalidate()
            flight = nil
        }

        /// Two fingers on the trackpad move the window. There is nothing to
        /// scroll here — the window holds one picture — so the gesture is free
        /// to mean the thing you actually want it to mean.
        ///
        /// And the pointer travels with it. Moving the window alone leaves the
        /// cursor behind: it drifts towards the edge, falls out, and the window
        /// stops answering mid-gesture. Carrying it keeps it at the same place
        /// in the frame, so the window can be pushed as far as the screen goes.
        override func scrollWheel(with event: NSEvent) {
            guard let window else { return }
            land()
            // Only while fingers are actually down. Letting the glide continue
            // would fling the pointer across the screen after them.
            guard event.momentumPhase == [] else { return }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard dx != 0 || dy != 0 else { return }

            let spot = window.frame.origin
            window.setFrameOrigin(NSPoint(x: spot.x + dx, y: spot.y - dy))

            // Screen coordinates run up from the bottom, the cursor's run down
            // from the top of the first display.
            guard let ground = NSScreen.screens.first else { return }
            let mouse = NSEvent.mouseLocation
            CGWarpMouseCursorPosition(
                CGPoint(
                    x: mouse.x + dx,
                    y: ground.frame.height - (mouse.y - dy)
                )
            )
            // Without this the pointer and the physical trackpad stay parted
            // for a moment, and the next flick arrives from the wrong place.
            CGAssociateMouseAndMouseCursorPosition(1)
        }

        /// A pinch sizes it about the pointer: whatever is under your fingers
        /// stays under your fingers, and the rest grows away from it. Sizing
        /// about the centre instead makes the picture slide sideways under a
        /// hand that never moved, which is what felt wrong.
        private var pinching: CGFloat = 0

        override func magnify(with event: NSEvent) {
            guard let window else { return }
            land()
            if event.phase == .began { pinching = 0 }
            pinching += event.magnification

            // Every event would mean a window resize, a web view relayout and a
            // video re-fit sixty times a second, which is the stutter. Moving
            // in steps of a fiftieth is below what an eye reads as a jump and
            // an order of magnitude less work.
            guard abs(pinching) > 0.02 else { return }
            let by = pinching
            pinching = 0
            resize(
                to: window.frame.width * (1 + by),
                from: window.frame,
                around: NSEvent.mouseLocation
            )
        }

        private func resize(to width: CGFloat, from was: NSRect, around anchor: NSPoint? = nil) {
            guard let window, was.width > 0 else { return }
            let limit = NSScreen.main?.visibleFrame.width ?? 1600
            // Keeps the shape: a video window that can be squashed is a video
            // window showing bars.
            let wide = min(max(window.minSize.width, width), limit * 0.85)
            let tall = wide * was.height / was.width

            let spot: NSPoint
            if let anchor {
                // Where the pointer sits within the window, as a fraction, kept
                // at the same fraction of the new one.
                let across = (anchor.x - was.minX) / was.width
                let up = (anchor.y - was.minY) / was.height
                spot = NSPoint(x: anchor.x - across * wide, y: anchor.y - up * tall)
            } else {
                spot = NSPoint(x: was.minX, y: was.maxY - tall)
            }
            // Not display: true — asking for an immediate redraw on every step
            // is what makes a live resize stutter. The next frame is soon
            // enough.
            window.setFrame(
                NSRect(x: spot.x, y: spot.y, width: wide, height: tall),
                display: false
            )
        }

        @objc private func pressedClose() { onClose?() }
        @objc private func pressedReturn() { onReturn?() }
        @objc private func pressedRewind() { onSkip?(-15) }
        @objc private func pressedForward() { onSkip?(15) }
        @objc private func pressedPause() {
            playing.toggle()
            onPlayPause?()
        }

        /// How far through, along the bottom edge. Quiet enough to ignore.
        final class Line: NSView {
            var through: Double = 0 {
                didSet { needsDisplay = true }
            }

            override func draw(_ dirty: NSRect) {
                NSColor(white: 1, alpha: 0.22).setFill()
                bounds.fill()
                NSColor(white: 1, alpha: 0.85).setFill()
                NSRect(x: 0, y: 0, width: bounds.width * through, height: bounds.height).fill()
            }

            override func hitTest(_ point: NSPoint) -> NSView? { nil }
        }
    }
}

/// Sites with a player worth following into the little window.
///
/// Anywhere else, a playing video is as likely to be a background as a film,
/// and the difference isn't something a script can tell from the outside. So
/// the list is of places people go to watch, and the shortcut covers the rest.
enum Players {
    /// A host suffix, and for a few shops that also stream, the path that
    /// separates the film from the product page.
    private static let known: [(host: String, path: String?)] = [
        ("youtube.com", nil), ("youtu.be", nil), ("netflix.com", nil),
        ("primevideo.com", nil), ("amazon.com", "/gp/video"), ("amazon.fr", "/gp/video"),
        ("amazon.co.uk", "/gp/video"), ("amazon.de", "/gp/video"),
        ("disneyplus.com", nil), ("tv.apple.com", nil), ("twitch.tv", nil),
        ("vimeo.com", nil), ("dailymotion.com", nil), ("max.com", nil), ("hbomax.com", nil),
        ("canalplus.com", nil), ("mycanal.fr", nil), ("arte.tv", nil), ("france.tv", nil),
        ("tf1.fr", nil), ("6play.fr", nil), ("crunchyroll.com", nil), ("plex.tv", nil),
        ("peacocktv.com", nil), ("hulu.com", nil), ("paramountplus.com", nil),
        ("molotov.tv", nil), ("ocs.fr", nil), ("mubi.com", nil), ("criterionchannel.com", nil),
        ("ted.com", nil), ("nebula.tv", nil), ("curiositystream.com", nil),
    ]

    static func knows(_ url: URL?) -> Bool {
        guard let url, let host = url.host()?.lowercased() else { return false }
        let path = url.path().lowercased()
        return known.contains { entry in
            guard host == entry.host || host.hasSuffix("." + entry.host) else { return false }
            guard let needle = entry.path else { return true }
            return path.hasPrefix(needle)
        }
    }
}

/// A panel that takes key status without bringing the whole app forward.
///
/// Borderless windows refuse to become key by default, and a window that never
/// becomes key is a window the system stops routing gestures to.
private final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum Isolate {
    /// A video worth floating: playing, not ended, a frame to show. Reads `v`.
    static let live = "(!v.paused && !v.ended && v.readyState >= 2)"

    /// Pinned inline on the floated video and undone on landing.
    static let videoStyle = """
    {'position': 'fixed', 'top': '0', 'left': '0', 'width': '100vw', 'height': '100vh',
     'margin': '0', 'padding': '0', 'border': '0', 'max-width': 'none', 'max-height': 'none',
     'object-fit': 'contain', 'object-position': 'center center', 'transform': 'none',
     'animation': 'none', 'transition': 'none', 'visibility': 'visible', 'z-index': '2147483647'}
    """

    /// Pinned on every ancestor of the floated video. A transformed, filtered
    /// or contained ancestor re-anchors position:fixed to itself; a clipping
    /// one (YouTube's #movie_player sits 56pt down, below the masthead, with
    /// overflow:hidden) still clips the fixed video in WebKit's compositor.
    /// Either way the top of the window shows the black page as a band.
    static let ancestorStyle = """
    {'transform': 'none', 'filter': 'none', 'perspective': 'none', 'will-change': 'auto',
     'backdrop-filter': 'none', 'contain': 'none', 'container-type': 'normal',
     'translate': 'none', 'rotate': 'none', 'scale': 'none', 'animation': 'none',
     'transition': 'none', 'overflow': 'visible', 'clip-path': 'none'}
    """

    /// Everything but the video, out of the way. Visibility is inherited, so
    /// hiding the body and turning it back on for the video alone leaves the
    /// player's own machinery running untouched — which is what keeps the
    /// stream alive where cutting the DOM about would kill it.
    static let on = """
    (function () {
      // Inline `!important` beats every site stylesheet, including player
      // rules built on IDs and the player's own inline styles.
      var videoStyle = \(videoStyle), ancestorStyle = \(ancestorStyle);
      function pin(el, style) {
        for (var p in style) el.style.setProperty(p, style[p], 'important');
      }
      function unpin(el, style) {
        for (var p in style) { try { el.style.removeProperty(p); } catch (e) {} }
      }
      function pinVideo(v) { if (v) pin(v, videoStyle); }
      function pinAncestors(v) {
        unpinAncestors();
        if (!v) return;
        var chain = [];
        for (var e = v.parentElement; e && e !== document.documentElement; e = e.parentElement) {
          pin(e, ancestorStyle);
          chain.push(e);
        }
        window.__satoriPinnedAncestors = chain;
      }
      function unpinAncestors() {
        (window.__satoriPinnedAncestors || []).forEach(function (e) { unpin(e, ancestorStyle); });
        window.__satoriPinnedAncestors = [];
      }
      function hideChrome(v) {
        unhideChrome();
        if (!v || !document.body) return;
        var chain = [];
        var c = v;
        while (c) {
          chain.push(c);
          if (c === document.body) break;
          c = c.parentElement;
        }
        var hidden = [];
        var kids = document.body.children;
        for (var i = 0; i < kids.length; i++) {
          var k = kids[i];
          var tag = (k.tagName || '').toLowerCase();
          if (tag === 'script' || tag === 'style') continue;
          if (chain.indexOf(k) >= 0) continue;
          try { k.style.setProperty('display', 'none', 'important'); hidden.push(k); } catch (e2) {}
        }
        window.__satoriHiddenChrome = hidden;
      }
      function unhideChrome() {
        var list = window.__satoriHiddenChrome || [];
        for (var i = 0; i < list.length; i++) {
          try { list[i].style.removeProperty('display'); } catch (e) {}
        }
        window.__satoriHiddenChrome = [];
      }
      function bestPlaying() {
        var videos = document.querySelectorAll('video');
        var best = null, area = 0;
        for (var i = 0; i < videos.length; i++) {
          var v = videos[i];
          if (!\(live)) continue;
          var box = v.getBoundingClientRect();
          if (box.width * box.height >= area) { area = box.width * box.height; best = v; }
        }
        return best;
      }
      function fullPin(v) {
        if (!v) return;
        var prev = document.querySelector('[data-satori-float]');
        if (prev && prev !== v) {
          unpin(prev, videoStyle);
          try { prev.removeAttribute('data-satori-float'); } catch (e) {}
        }
        try { v.setAttribute('data-satori-float', ''); } catch (e) {}
        pinVideo(v);
        pinAncestors(v);
        hideChrome(v);
      }
      window.__satoriPinVideo = pinVideo;
      window.__satoriPinAncestors = pinAncestors;
      window.__satoriHideChrome = hideChrome;
      window.__satoriBestPlaying = bestPlaying;
      window.__satoriFullPin = fullPin;

      var best = bestPlaying();
      if (!best) return 'none';
      fullPin(best);

      var sheet = document.getElementById('office-float');
      if (!sheet) {
        sheet = document.createElement('style');
        sheet.id = 'office-float';
        (document.head || document.documentElement).appendChild(sheet);
      }
      sheet.textContent = [
        'html.satori-floating, html.satori-floating body {',
        'background:#000 !important; overflow:hidden !important; margin:0 !important; padding:0 !important}',
        'html.satori-floating body > * { visibility:hidden !important }',
        'html.satori-floating [data-satori-float] {',
        'visibility:visible !important; position:fixed !important;',
        'left:0 !important; top:0 !important;',
        'width:100vw !important; height:100vh !important;',
        'margin:0 !important; padding:0 !important; border:0 !important;',
        'max-width:none !important; max-height:none !important;',
        'object-fit:contain !important; object-position:center center !important;',
        'transform:none !important; animation:none !important; transition:none !important;',
        'z-index:2147483647 !important}',
        // The player's own controls would sit under ours, and two sets of
        // buttons on one small window is one set too many.
        'html.satori-floating [data-satori-float]::-webkit-media-controls {',
        'display:none !important}'
      ].join('');
      document.documentElement.classList.add('satori-floating');

      // The mark has to be defended.
      //
      // Everything but the marked element is hidden, so the moment a player
      // rebuilds its DOM — and they all do, on a quality change, an ad break,
      // a React re-render — the mark goes with the old element and the window
      // turns pure black while still holding a perfectly live page. That is the
      // black rectangle, and it is not an orphaned window at all.
      //
      // So the mark is put back on whatever is playing now, four times a
      // second, for as long as the page is out. The pin is re-applied each
      // tick too: the player can move the node to a new container (new
      // ancestors) or rewrite its style without dropping the mark.
      clearInterval(window.__satoriFloatWatch);
      window.__satoriFloatWatch = setInterval(function () {
        var marked = document.querySelector('[data-satori-float]');
        if (marked) {
          try {
            window.__satoriPinVideo(marked);
            window.__satoriPinAncestors(marked);
            window.__satoriHideChrome(marked);
          } catch (e) {}
          try {
            var r = marked.getBoundingClientRect();
            if (r && r.top > 2) {
              var best = window.__satoriBestPlaying();
              if (best) window.__satoriFullPin(best);
            }
          } catch (e) {}
          return;
        }
        var again = null;
        try { again = window.__satoriBestPlaying(); } catch (e) {}
        if (again) {
          try { window.__satoriFullPin(again); } catch (e) {}
        }
      }, 250);

      return 'floating';
    })();
    """

    /// Whether anything on the page could be floated right now. The same
    /// practical test as `on` — a video that is playing, not ended, and
    /// loaded enough to show a frame — without touching the DOM: no marks,
    /// no stylesheet, no watch interval. The tab pill reads this through
    /// `Tab.canFloat` so the pop-out icon only appears when it would work.
    static let probe = """
    (function () {
      try {
        var videos = document.querySelectorAll('video');
        for (var i = 0; i < videos.length; i++) {
          var v = videos[i];
          if (\(live)) return true;
        }
        return false;
      } catch (e) { return false; }
    })();
    """

    /// Stop or start it, and say which it is now.
    /// Step over the bit you missed, or back to it.
    static func skip(_ seconds: Double) -> String {
        """
        (function () {
          var video = document.querySelector('[data-satori-float]')
            || document.querySelector('video');
          if (!video) return false;
          video.currentTime = Math.max(0, video.currentTime + (\(seconds)));
          return true;
        })();
        """
    }

    /// How far through, and whether it is running.
    static let where_ = """
    (function () {
      var video = document.querySelector('[data-satori-float]')
        || document.querySelector('video');
      if (!video || !video.duration || !isFinite(video.duration)) return [0, true];
      return [video.currentTime / video.duration, !video.paused];
    })();
    """

    static let toggle = """
    (function () {
      var video = document.querySelector('[data-satori-float]')
        || document.querySelector('video');
      if (!video) return true;
      if (video.paused) { video.play(); } else { video.pause(); }
      return !video.paused;
    })();
    """

    static let off = """
    (function () {
      // The engine may have put the video in its own floating window as well —
      // some players ask for that themselves. Leaving one and not the other
      // leaves you with two.
      try {
        var out = document.querySelector('video[data-satori-float]')
          || document.querySelector('video');
        if (out) {
          if (out.webkitPresentationMode === 'picture-in-picture') {
            out.webkitSetPresentationMode('inline');
          }
          if (document.pictureInPictureElement && document.exitPictureInPicture) {
            document.exitPictureInPicture();
          }
        }
      } catch (e) {}

      clearInterval(window.__satoriFloatWatch);
      window.__satoriFloatWatch = null;
      try {
        var hidden = window.__satoriHiddenChrome || [];
        for (var h = 0; h < hidden.length; h++) {
          try { hidden[h].style.removeProperty('display'); } catch (e) {}
        }
      } catch (e) {}
      window.__satoriHiddenChrome = [];
      document.documentElement.classList.remove('satori-floating');
      var sheet = document.getElementById('office-float');
      if (sheet) sheet.textContent = '';
      // Undo the inline pinning from `on`.
      var videoStyle = \(videoStyle), ancestorStyle = \(ancestorStyle);
      (window.__satoriPinnedAncestors || []).forEach(function (e) {
        for (var p in ancestorStyle) { try { e.style.removeProperty(p); } catch (x) {} }
      });
      window.__satoriPinnedAncestors = [];
      var video = document.querySelector('[data-satori-float]');
      if (video) {
        for (var p in videoStyle) { try { video.style.removeProperty(p); } catch (e) {} }
        video.removeAttribute('data-satori-float');
      }
      window.__satoriPinVideo = null;
      window.__satoriPinAncestors = null;
      window.__satoriHideChrome = null;
      window.__satoriBestPlaying = null;
      window.__satoriFullPin = null;
      return 'landed';
    })();
    """
}

/// Tells its tab when a floatable video comes or goes, so the tab pill can
/// show the pop-out icon only while floating would actually work.
///
/// Same criteria as `Isolate.on`/`Isolate.probe`, reported on media and DOM
/// events rather than polled: play, pause, ended, loads, and nodes arriving
/// or leaving. Main frame only, matching what a float attempt would find.
final class FloatRelay: NSObject, WKScriptMessageHandler {
    static let name = "satoriFloat"

    weak var tab: Tab?

    static let watch = """
    (function () {
      if (window.__satoriFloat) return;
      window.__satoriFloat = true;
      var last = null;
      function check() {
        try {
          var ok = false;
          var videos = document.querySelectorAll('video');
          for (var i = 0; i < videos.length; i++) {
            var v = videos[i];
            if (\(Isolate.live)) { ok = true; break; }
          }
          if (ok !== last) {
            last = ok;
            window.webkit.messageHandlers.satoriFloat.postMessage({ floatable: ok });
          }
        } catch (e) {}
      }
      function soon() { requestAnimationFrame(function () { check(); }); }
      ['play', 'pause', 'ended', 'emptied', 'loadeddata', 'canplay', 'seeked'].forEach(function (n) {
        document.addEventListener(n, soon, true);
      });
      var delayed = null;
      new MutationObserver(function () {
        if (delayed) return;
        delayed = setTimeout(function () { delayed = null; check(); }, 300);
      }).observe(document.documentElement, { childList: true, subtree: true });
      if (document.readyState === 'complete') { check(); }
      else { window.addEventListener('load', check); }
      setTimeout(check, 700);
      setTimeout(check, 2200);
    })();
    """

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let ok = body["floatable"] as? Bool
        else { return }
        MainActor.assumeIsolated { [weak self] in
            guard let self, let tab else { return }
            tab.setFloatAvailability(ok)
        }
    }
}

