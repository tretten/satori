import AppKit
import SwiftUI

// Every action with a keystroke, and the combos the person taught it.
//
// Defaults below are the browser's own and keep working untouched: only an
// action with a taught combo answers through `overrideMatch`, so teaching
// never disturbs the rest. Combos live in the settings store by action name;
// teaching happens in Settings › Shortcuts, one row at a time.

enum ShortcutAction: String, CaseIterable, Identifiable {
    case address, switchTab, newTab, closeTab, reopenTab
    case sidebar, reader, hiding, float, back, forward
    var id: String { rawValue }

    var title: String {
        switch self {
        case .address: return "Address"
        case .switchTab: return "Switch tab"
        case .newTab: return "New tab"
        case .closeTab: return "Close tab"
        case .reopenTab: return "Reopen closed tab"
        case .sidebar: return "Tabs in a sidebar"
        case .reader: return "Reading mode"
        case .hiding: return "Hide something on this site"
        case .float: return "Float the video"
        case .back: return "Back"
        case .forward: return "Forward"
        }
    }

    var preset: KeyBinding {
        switch self {
        case .address: return KeyBinding(key: "l", flags: .command)
        case .switchTab: return KeyBinding(key: "k", flags: .command)
        case .newTab: return KeyBinding(key: "t", flags: .command)
        case .closeTab: return KeyBinding(key: "w", flags: .command)
        case .reopenTab: return KeyBinding(key: "t", flags: [.command, .shift])
        case .sidebar: return KeyBinding(key: "s", flags: [.command, .shift])
        case .reader: return KeyBinding(key: "r", flags: [.command, .shift])
        case .hiding: return KeyBinding(key: "h", flags: [.command, .shift])
        case .float: return KeyBinding(key: "p", flags: [.command, .shift])
        case .back: return KeyBinding(key: "[", flags: .command)
        case .forward: return KeyBinding(key: "]", flags: .command)
        }
    }

    @MainActor
    func perform(on browser: Browser) {
        switch self {
        case .address: browser.edit()
        case .switchTab: browser.summon()
        case .newTab: browser.newTab()
        case .closeTab: if let tab = browser.active { browser.close(tab) }
        case .reopenTab: browser.reopen()
        case .sidebar: browser.toggleSidebar()
        case .reader: browser.toggleReader()
        case .hiding: browser.toggleHiding()
        case .float: browser.toggleFloat()
        case .back: browser.back()
        case .forward: browser.forward()
        }
    }
}

/// One combo: a character and the modifiers with it. Only ⌘ combos are
/// teachable — anything without ⌘ would steal ordinary typing.
struct KeyBinding: Equatable {
    var key: String
    var flags: NSEvent.ModifierFlags

    init(key: String, flags: NSEvent.ModifierFlags) {
        self.key = key.lowercased()
        self.flags = flags.intersection([.command, .control, .option, .shift])
    }

    init?(saved: String) {
        let parts = saved.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let raw = UInt(parts[0]), parts[1].count == 1 else { return nil }
        self.init(key: parts[1], flags: NSEvent.ModifierFlags(rawValue: raw))
    }

    var saved: String { "\(flags.rawValue):\(key)" }

    /// ⌘⇧T. What the Shortcuts page shows.
    var display: String {
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        return out + key.uppercased()
    }

    var keyEquivalent: KeyEquivalent { KeyEquivalent(Character(key)) }

    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}

extension Preferences {
    /// The combo answering for this action: taught, or the preset.
    func binding(for action: ShortcutAction) -> KeyBinding {
        shortcutOverrides[action.rawValue].flatMap(KeyBinding.init(saved:)) ?? action.preset
    }

    func setBinding(_ binding: KeyBinding, for action: ShortcutAction) {
        var taught = shortcutOverrides
        taught[action.rawValue] = binding.saved
        shortcutOverrides = taught
    }

    func resetBinding(_ action: ShortcutAction) {
        var taught = shortcutOverrides
        taught.removeValue(forKey: action.rawValue)
        shortcutOverrides = taught
    }

    /// A taught combo matching this press, if any. Presets never match here —
    /// they keep their own road through the key monitor.
    func overrideMatch(key: String, flags: NSEvent.ModifierFlags) -> ShortcutAction? {
        let want = flags.intersection([.command, .control, .option, .shift])
        return ShortcutAction.allCases.first {
            guard let saved = shortcutOverrides[$0.rawValue],
                  let binding = KeyBinding(saved: saved)
            else { return false }
            return binding.key == key && binding.flags == want
        }
    }
}

/// The keystroke catcher behind one Shortcuts row. While it listens, the
/// app's own monitor stands down (see `prefs.recording`), so teaching a
/// combo never fires one. Esc cancels, ⌫ gives the preset back.
@MainActor
final class ShortcutRecorder: ObservableObject {
    private var monitor: Any?

    func start(_ action: ShortcutAction, prefs: Preferences, touched: @escaping () -> Void) {
        stop(prefs: prefs)
        prefs.recording = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return nil }
            if event.keyCode == 53 { self.stop(prefs: prefs); return nil }
            if event.keyCode == 51 {
                prefs.resetBinding(action)
                touched()
                self.stop(prefs: prefs)
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command),
                  let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1
            else { return nil }
            prefs.setBinding(KeyBinding(key: chars, flags: flags), for: action)
            touched()
            self.stop(prefs: prefs)
            return nil
        }
    }

    func stop(prefs: Preferences) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        prefs.recording = nil
    }
}
