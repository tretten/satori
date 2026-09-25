import AppKit
import Carbon

/// The address field borrows the English layout while it holds the caret.
///
/// Addresses are ASCII, so typing one under a Cyrillic or other non-Latin
/// layout produces nothing usable. On focus the scope saves the current
/// layout and selects an English one; when the field is done it puts the
/// saved layout back. Everything is a no-op when there is nothing to do:
/// already English, no English source installed, focus failed, or the field
/// is mid-composition with an IME.
final class AddressInputScope {
    private var saved: TISInputSource?
    private var engaged = false

    /// Layouts English enough to type an address with, for sources whose
    /// language list is missing or unhelpful.
    private static let englishIDs: Set<String> = [
        "com.apple.keylayout.US",
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.British",
        "com.apple.keylayout.Irish",
        "com.apple.keylayout.Australian",
        "com.apple.keylayout.Canadian",
        "com.apple.keylayout.USInternational-PC",
    ]

    /// When several English layouts are installed, US wins, then ABC.
    private static let preference = [
        "com.apple.keylayout.US",
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.British",
    ]

    /// Save the current layout and select English. Idempotent; no-op when
    /// already English, when no English keyboard source exists, when the
    /// field has no window, or while marked (composing) text is present.
    func begin(for field: NSTextField) {
        guard Thread.isMainThread else { return }
        guard !engaged else { return }
        guard field.window != nil else { return }
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        if Self.isEnglish(current) { return }
        guard let english = Self.englishKeyboardSource() else { return }
        saved = current
        engaged = true
        _ = TISSelectInputSource(english)
    }

    /// Put the saved layout back. Idempotent. Passing the field editor lets
    /// a mid-composition Return skip the restore; the later end-editing or
    /// teardown call (with no editor) still restores, so the borrow never
    /// leaks. Call the bare `end()` when editing is over or the view is
    /// going away.
    func end(editor: NSTextView? = nil) {
        guard Thread.isMainThread else { return }
        guard engaged, let previous = saved else {
            engaged = false
            saved = nil
            return
        }
        if let editor, editor.hasMarkedText() { return }
        saved = nil
        engaged = false
        _ = TISSelectInputSource(previous)
    }

    private static func isEnglish(_ source: TISInputSource) -> Bool {
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let array = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as NSArray
            if let langs = array as? [String],
               langs.contains(where: { $0 == "en" || $0.hasPrefix("en-") || $0.hasPrefix("en_") }) {
                return true
            }
        }
        if let id = identifier(of: source), englishIDs.contains(id) { return true }
        return false
    }

    private static func englishKeyboardSource() -> TISInputSource? {
        guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() else { return nil }
        let count = CFArrayGetCount(list)
        var candidates: [TISInputSource] = []
        for i in 0..<count {
            guard let value = CFArrayGetValueAtIndex(list, i) else { continue }
            let source = Unmanaged<TISInputSource>.fromOpaque(value).takeUnretainedValue()
            if isKeyboardSelectable(source), isEnglish(source) {
                candidates.append(source)
            }
        }
        guard !candidates.isEmpty else { return nil }
        for want in preference {
            if let match = candidates.first(where: { identifier(of: $0) == want }) { return match }
        }
        return candidates.first
    }

    private static func isKeyboardSelectable(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else {
            return false
        }
        let category = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        guard category == (kTISCategoryKeyboardInputSource as String) else { return false }
        guard let capablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            return false
        }
        let capable = Unmanaged<CFBoolean>.fromOpaque(capablePtr).takeUnretainedValue()
        return CFBooleanGetValue(capable)
    }

    private static func identifier(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
