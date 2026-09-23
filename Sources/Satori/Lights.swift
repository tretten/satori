import AppKit

// The traffic lights, where a Mac app with a toolbar has them — set in from the
// corner and centred in the strip's height — without the toolbar.
//
// An empty toolbar is the public way to move them, and it was how this window
// did it. On macOS 26 a toolbar also rounds the window's corners almost twice
// as much: 31.5 points against 17.5 for a window without one, measured, and
// 17.5 is what Claude's window and the Finder have. So the window has no
// toolbar, and the three buttons are put where one would have put them, by
// hand — which is how Claude's own window does it. AppKit lays its title bar
// out again whenever it sees fit (a resize, full screen, the window becoming
// key), so every time it does, the buttons are put back.

@MainActor
final class Lights: NSObject {
    /// Where the close button's centre goes, from the window's top-left: set
    /// in tighter than a unified toolbar would, which Metrics.lights and
    /// sideLights are measured from.
    static let centre = CGPoint(x: 21, y: 24)

    private static var kept: [ObjectIdentifier: Lights] = [:]

    /// Starts looking after a window's lights, once. `moved` hears each time
    /// they have been put in place.
    static func keep(_ window: NSWindow, moved: @escaping () -> Void) {
        guard kept[ObjectIdentifier(window)] == nil else { return }
        kept[ObjectIdentifier(window)] = Lights(window, moved: moved)
    }

    private weak var window: NSWindow?
    private let moved: () -> Void
    private var placing = false
    /// AppKit's own spacing between the three, tightened past Safari's 23
    /// by request.
    private let spacing: CGFloat = 20

    private init(_ window: NSWindow, moved: @escaping () -> Void) {
        self.window = window
        self.moved = moved
        super.init()
        // Regular metrics, never compact: Tahoe shrinks controls for windows
        // that ask. The buttons themselves are AppKit's own, in place —
        // swapping them out zombies the theme frame's raw pointers to the
        // originals (crashed on launch, 23 Sep 2026), so only the row's place
        // is ours, never the instances.
        if #available(macOS 26, *) {
            window.contentView?.prefersCompactControlSizeMetrics = false
        }
        let centre = NotificationCenter.default
        for name in [
            NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSWindow.didExitFullScreenNotification, NSWindow.didChangeScreenNotification,
        ] {
            centre.addObserver(self, selector: #selector(place), name: name, object: window)
        }
        // The title bar's own views moving is the surest sign AppKit has just
        // laid them out again. The buttons take a fixed frame: left to the
        // bar's resizing they stretch with it, into ovals.
        let buttons = self.buttons
        buttons.forEach { $0.autoresizingMask = [] }
        if let bar = buttons.first?.superview, let container = bar.superview {
            for view in [container, bar] + buttons {
                view.postsFrameChangedNotifications = true
                centre.addObserver(self, selector: #selector(place), name: NSView.frameDidChangeNotification, object: view)
            }
        }
        place()
    }

    private var buttons: [NSButton] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window?.standardWindowButton($0) }
    }

    @objc private func place() {
        // Full screen keeps its title bar in a window of its own, laid out by
        // macOS; it is left to it.
        guard !placing, let window, !window.styleMask.contains(.fullScreen) else { return }
        let buttons = self.buttons
        guard buttons.count == 3, let bar = buttons[0].superview, let container = bar.superview else { return }
        placing = true
        defer { placing = false }

        // A title bar as tall as the strip, so the buttons can sit lower in it.
        let height = Metrics.strip
        var frame = container.frame
        if frame.height != height || frame.maxY != window.frame.height {
            frame.size.height = height
            frame.origin.y = window.frame.height - height
            container.frame = frame
        }
        // Only the row moves; the spacing is AppKit's doing.
        for (index, button) in buttons.enumerated() {
            let size = button.frame.size
            let origin = NSPoint(
                x: Lights.centre.x - size.width / 2 + CGFloat(index) * spacing,
                y: bar.bounds.height - Lights.centre.y - size.height / 2
            )
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
        moved()
    }
}
