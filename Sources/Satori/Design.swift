import SwiftUI
import AppKit

// Lifted from Office Inspiration, with the ground turned white: there the work
// floats on an off-white canvas, here the page *is* the ground and everything
// the browser draws has to get out of its way.
//
// Every colour is a pair — one for a light window, one for a dark — and
// resolves itself against whatever appearance the window has. The window
// takes its appearance from the app, and the app from Settings › Appearance:
// dark, light, or whatever the Mac is doing. Nothing else in the code knows
// which it is.
enum Palette {
    static let ground = Color(nsColor: NS.ground)
    static let ink = Color(nsColor: NS.ink)             // neutral-900 · neutral-100
    static let muted = Color(nsColor: NS.muted)         // neutral-500
    static let faint = Color(nsColor: NS.faint)         // neutral-300 · neutral-700
    static let hairline = Color(nsColor: NS.hairline)   // neutral-200 · neutral-800
    static let wash = Color(nsColor: NS.wash)           // the live tab
    static let hover = Color(nsColor: NS.hover)         // the one under the pointer

    /// The same colours for the AppKit corners of the app — a text field's
    /// ink, a window's background — which want an NSColor and keep it.
    enum NS {
        static let ground = pair(1.0, 0.11)
        static let ink = pair(0.09, 0.93)
        static let muted = pair(0.55, 0.58)
        static let faint = pair(0.83, 0.32)
        static let hairline = pair(0.91, 0.20)
        static let wash = pair(0.937, 0.175)
        static let hover = pair(0.965, 0.15)
        /// The resting traffic lights, drawn by hand when the app is behind.
        static let resting = pair(0.80, 0.30)

        private static func pair(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
            NSColor(name: nil) { appearance in
                let dim = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(white: dim ? dark : light, alpha: 1)
            }
        }
    }

    /// Opaque text and vector icons that sit on a website tint.
    ///
    /// Nil tint means no usable page colour: the caller keeps `ink`/`muted`.
    /// Otherwise WCAG black-versus-white selection — white wins below a
    /// relative luminance of ~0.179, where the two contrasts cross — with the
    /// idle variant dimmed to 0.65 so live (1.0) > hover (0.7) > idle keeps
    /// the row's existing hierarchy.
    static func foreground(on tint: Tint?, dimmed: Bool = false) -> Color {
        guard let tint else { return dimmed ? muted : ink }
        let base: Color = tint.luminance > 0.179 ? .black : .white
        return dimmed ? base.opacity(0.65) : base
    }
}

/// A website-provided opaque tint: sRGB components plus WCAG luminance.
///
/// Kept as numbers rather than reading them back out of a `Color`, which
/// cannot reliably round-trip under dynamic macOS appearance. `color` is the
/// opaque SwiftUI colour worn by the bar; `luminance` drives the contrast
/// helper above.
struct Tint: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    /// Bytes from page JS (0...255).
    init(bytes r: Double, g: Double, b: Double) {
        self.init(red: r / 255, green: g / 255, blue: b / 255)
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    /// WCAG relative luminance, 0...1.
    var luminance: Double {
        func lin(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }
}

extension Tint {
    /// Two hex digits a channel, as a person would read it: `#E8F0E4`.
    var hex: String {
        String(format: "#%02X%02X%02X", Int(red * 255 + 0.5), Int(green * 255 + 0.5), Int(blue * 255 + 0.5))
    }

    init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(bytes: Double(value >> 16 & 0xFF), g: Double(value >> 8 & 0xFF), b: Double(value & 0xFF))
    }

    /// A small square of the colour, for a menu.
    var swatch: NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor(srgbRed: red, green: green, blue: blue, alpha: 1).setFill()
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3.5, yRadius: 3.5)
            path.fill()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The colour picked by hand for a site (tab menu › Tab Color), which it
    /// wears instead of whatever its pages offer.
    static func chosen(for host: String?) -> Tint? {
        guard let host else { return nil }
        let sites = Store.settings.dictionary(forKey: "tint.sites") as? [String: String]
        return sites?[host].flatMap(Tint.init(hex:))
    }

    /// Nil gives the site back its own colour.
    static func choose(_ tint: Tint?, for host: String) {
        var sites = Store.settings.dictionary(forKey: "tint.sites") as? [String: String] ?? [:]
        sites[host] = tint?.hex
        Store.settings.set(sites, forKey: "tint.sites")
    }
}

/// Dark, light, or the Mac's own — the one choice that colours everything.
enum Look: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "Auto"
        }
    }

    /// What the app is told to be. Nothing, for "system": the app then
    /// follows the Mac, and changes with it.
    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }

    /// Set on the app rather than on the window, so every panel, alert and
    /// sheet — and every page, which follows the window it is in — agrees.
    ///
    /// Never from inside whatever is happening when it is asked for: the
    /// switch in Settings changes it from within an animation, over a panel
    /// in transition, and re-skinning every window in the middle of that is
    /// how a window ends up with a layer that takes clicks and shows
    /// nothing. The next turn of the run loop is soon enough.
    func apply() {
        let wanted = appearance
        DispatchQueue.main.async {
            guard NSApp.appearance !== wanted, NSApp.appearance?.name != wanted?.name else { return }
            NSApp.appearance = wanted
        }
    }
}

enum Metrics {
    /// The tab strip. The window's title bar is grown to match it so the
    /// traffic lights come down with the tabs — otherwise giving the row room
    /// to breathe just leaves it sitting below three buttons it used to line
    /// up with. 44 points: a little under Safari's 48.
    static let strip: CGFloat = 44
    /// The top edge as the window has it: the strip, or a web app's bar —
    /// no tabs to hold, so no taller than a title bar needs.
    static var bar: CGFloat { WebApp.on ? 34 : strip }
    /// How far below the bar's middle its row sits. The fade under a web
    /// app's bar reads as more bar, so a row centred on the bar looked high.
    static var barDrop: CGFloat { WebApp.on ? 3 : 0 }
    /// The page goes edge to edge; only its top corners are rounded, against
    /// the strip.
    static let pageInset: CGFloat = 0
    static let pageRadius: CGFloat = 4
    /// Where the helm starts. The traffic lights are hand-placed (Lights.centre
    /// x 21, spacing 20, ~12pt buttons: right edge ~67), so this leaves them
    /// ~11 of air on their right — close to the window's own left air — and
    /// puts back/forward right after the lights.
    static let lights: CGFloat = 78
    /// Back and forward: two doors and the air before the next
    /// one. In the strip they stand right after the lights; in the sidebar
    /// right of them instead.
    static let helm: CGFloat = 2 * 26 + 2 + 8
    /// The same three doors again, in the sidebar, where they sit right of
    /// the lights instead. The column already has 10 of horizontal padding
    /// of its own before this even starts, so this is the lights' own edge
    /// (106) less that padding, plus a sliver of air — not the full breathing
    /// room a tab row gets, because the sidebar's minimum width doesn't have
    /// it to give.
    static let sideLights: CGFloat = 99
    /// Tabs are a fixed width rather than the width of their titles, so the
    /// cross always lands in the same place and the row never rearranges
    /// itself while you read it. They give way when there are too many:
    /// narrower than tabTitled they show their site's mark alone, and they
    /// stop at tabMinWidth, the mark and its air. Past that the row scrolls,
    /// inside its own edges.
    static let tabWidth: CGFloat = 186
    static let tabTitled: CGFloat = 80
    static let tabMinWidth: CGFloat = 36
    static let tabGap: CGFloat = 2
    /// A pinned tab is a square the height of the row, holding one letter.
    static let pinWidth: CGFloat = 30
    /// The square at the end of the row that opens a new page.
    static let plusWidth: CGFloat = 30
    /// The address field, in both the places it shows up.
    static let fieldWidth: CGFloat = 560
    /// The column of titles down the left, in the way that has one.
    static let side: CGFloat = 232
    static let sideMin: CGFloat = 176
    static let sideMax: CGFloat = 440
}

// One spring for anything that moves between two places, one for anything that
// arrives or leaves. Using the same two everywhere is most of why a thing feels
// like a single piece of software rather than a pile of views.
enum Motion {
    static let settle = Animation.spring(response: 0.30, dampingFraction: 1.0)
    static let quick = Animation.easeOut(duration: 0.14)
    /// The address field arriving and leaving: quicker than `settle`, because
    /// it answers a key and the hand is already waiting to type.
    static let field = Animation.spring(response: 0.22, dampingFraction: 1.0)
}

/// Press feedback on the way down, not on release: the control answers the
/// instant it is held.
struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The app's own icon, for the welcome walk and the About page — the bundle
/// icon already on the Dock, not a separate mark. Falls back to a neutral
/// glyph when the bundle icon isn't there (tests, previews).
struct AppIcon: View {
    var size: CGFloat
    var body: some View {
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(Palette.muted)
                    .frame(width: size, height: size)
            }
        }
    }
}

/// Wrong address, said without a dialog: the field shivers and stops.
struct Shake: GeometryEffect {
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        // Three there-and-backs, tapering to nothing, so it settles rather than
        // stopping mid-swing.
        let decay = 1 - travel
        return ProjectionTransform(
            CGAffineTransform(translationX: sin(travel * .pi * 6) * 7 * decay, y: 0)
        )
    }
}
