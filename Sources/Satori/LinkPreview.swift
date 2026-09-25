import SwiftUI
import WebKit

// The address of the link under the pointer, in a small bubble at the page's
// bottom-left — the way Safari and Chrome do it.
//
// WebKit does not report link hover natively, so the page says so itself: a
// small delegated `mouseover`/`mouseout` pair over `a[href]` posts the
// resolved URL through `LinkRelay`, following the existing relay pattern
// (`FloatRelay`/`ScrollRelay` style: handler registered in `Tab.build`,
// script injected in `Tab.arm`, removed in `Tab.discard`).
//
// Rules:
// - Event-driven only: document-level `mouseover`/`mouseout` in the capture
//   phase, so nothing is polled and no per-element listeners are installed.
//   A `mouseover` posts inside `requestAnimationFrame` and only when the
//   resolved URL differs from the last one sent; `mouseout` posts only when
//   the pointer leaves the anchor entirely (moving between children of the
//   same link is silent, and moving straight onto another link lets that
//   link's own `mouseover` speak, so rapid hover changes swap the bubble
//   without flicker). No per-mousemove traffic beyond what the page already
//   dispatches.
// - Main frame only: injected `forMainFrameOnly: true`, plus a
//   `window.top !== window` guard. Hovers inside iframes never report.
// - DOM rebuilds are fine: delegation lives on the document, so links added
//   later (framework re-renders, SPA navigations) report with no
//   re-injection. `click` also hides, covering SPA route changes where the
//   document — and the pointer position — survive the navigation.
// - Schemes: any non-empty resolved URL is shown as-is (`https:`, `mailto:`,
//   `tel:`, …). Empty or missing `href` never posts — the bubble hides
//   instead. `javascript:` links are shown like any other scheme; the string
//   is only ever displayed, never evaluated. Each post is capped at 2048
//   characters so a hostile page cannot spray unbounded strings at the UI.
// - Never touches page behaviour: nothing is prevented, stopped or restyled,
//   so scrolling, clicks, text selection, find-in-page and reader mode keep
//   their semantics. The bubble itself is `allowsHitTesting(false)` and
//   hidden from accessibility (the link underneath stays the accessible
//   element), so it cannot steal clicks, selection or VoiceOver focus.
// - Blank tabs hold no document and send nothing; navigation, sleep and tab
//   switch clear the state natively (see `Tab.clearHover` callers), so a
//   bubble can never outlive its page.

/// Carries link hover reports from the page to its tab.
///
/// A content controller holds its handlers strongly, so this stands between
/// the two rather than the tab registering itself — otherwise a closed tab
/// is kept alive by the very page it was told to stop showing.
final class LinkRelay: NSObject, WKScriptMessageHandler {
    static let name = "satoriLinks"

    weak var tab: Tab?

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated { [weak self] in
            guard let self, let tab else { return }
            if body["hide"] as? Bool == true {
                tab.clearHover()
                return
            }
            guard let url = body["url"] as? String, !url.isEmpty else {
                tab.clearHover()
                return
            }
            tab.setHover(url)
        }
    }

    /// Delegated hover listeners. One closure and three listeners until a
    /// link is actually hovered; see the file header for the rules.
    static let watch = """
    (function () {
      if (window.__satoriLinks) return;
      window.__satoriLinks = true;
      if (window.top !== window) return;
      var last = null;
      var queued = null;
      function over(e) {
        var el = e.target && e.target.closest ? e.target.closest('a[href]') : null;
        if (!el) return;
        var raw = el.getAttribute('href');
        if (!raw || !raw.trim()) return;
        var url;
        try { url = new URL(raw, document.baseURI).href; }
        catch (err) { url = raw; }
        if (!url || url === last || url === queued) return;
        queued = url;
        requestAnimationFrame(function () {
          var next = queued;
          queued = null;
          if (!next || next === last) return;
          last = next;
          try { window.webkit.messageHandlers.\(name).postMessage({ url: next.slice(0, 2048) }); } catch (err) {}
        });
      }
      function out(e) {
        var from = e.target && e.target.closest ? e.target.closest('a[href]') : null;
        if (!from) return;
        var to = e.relatedTarget && e.relatedTarget.closest ? e.relatedTarget.closest('a[href]') : null;
        if (to) return;
        last = null;
        queued = null;
        try { window.webkit.messageHandlers.\(name).postMessage({ hide: true }); } catch (err) {}
      }
      function gone() {
        if (last === null) return;
        last = null;
        queued = null;
        try { window.webkit.messageHandlers.\(name).postMessage({ hide: true }); } catch (err) {}
      }
      document.addEventListener('mouseover', over, true);
      document.addEventListener('mouseout', out, true);
      document.addEventListener('click', function () { gone(); }, true);
      window.addEventListener('pagehide', gone, true);
    })();
    """
}

/// The bubble itself: the app's quiet voice — ground fill, hairline, soft
/// shadow — which follows light/dark through `Palette` automatically.
/// Opaque fill (no material), so Reduce Transparency needs no special case;
/// show/hide animates through `Motion.quick` unless Reduce Motion is on.
struct LinkBubble: View {
    let url: String

    var body: some View {
        Text(url)
            .font(.system(size: 11))
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: 520, alignment: .leading)
            .background(
                Palette.ground,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
