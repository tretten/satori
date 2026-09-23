import AppKit
import WebKit

// Right-click on a video, own menu.
//
// WebKit's own — Play, Mute, Loop, Full Screen, Picture in Picture, Download
// Video and the rest — looks complete, but its "Download Video" never reaches
// WKNavigationDelegate (a context menu's download isn't a navigation, so
// nothing the policy delegate sees applies to it) and goes nowhere audibly.
// The same was true of "Download Image", which is why ImageMenu.swift exists;
// this is its twin for <video>: the page's own menu steps aside for exactly
// one element, and this app's menu stands in for it. Playback items are
// re-done here through the element itself, so nothing that worked is lost.

/// What the menu found: where the video lives and how it is right now.
struct VideoState {
    let url: URL
    let tag: Int
    let paused: Bool
    let muted: Bool
    let looped: Bool
}

final class VideoRelay: NSObject, WKScriptMessageHandler {
    static let name = "satoriVideos"

    weak var tab: Tab?

    /// Every frame: a <video> reached through shadow roots still counts, via
    /// closest(). Only one with an address is worth the trip.
    static let watch = """
    (function () {
      if (window.__satoriVideos) return;
      window.__satoriVideos = true;
      var n = 0;
      document.addEventListener('contextmenu', function (e) {
        var el = e.target && e.target.closest ? e.target.closest('video') : null;
        if (!el || !el.currentSrc) return;
        n += 1;
        el.setAttribute('data-satori-video', String(n));
        e.preventDefault();
        window.webkit.messageHandlers.satoriVideos.postMessage({
          src: el.currentSrc, tag: n,
          paused: !!el.paused, muted: !!el.muted, loop: !!el.loop
        });
      }, true);
    })();
    """

    /// A command at the tagged element, found again by its tag.
    static func act(tag: Int, _ js: String) -> String {
        "(function(){var v=document.querySelector('[data-satori-video=\"\(tag)\"]');if(!v)return;\(js)})()"
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let src = body["src"] as? String,
              let url = URL(string: src),
              let tag = body["tag"] as? Int
        else { return }
        let state = VideoState(
            url: url, tag: tag,
            paused: (body["paused"] as? Bool) ?? true,
            muted: (body["muted"] as? Bool) ?? false,
            looped: (body["loop"] as? Bool) ?? false
        )
        MainActor.assumeIsolated { [weak self] in
            guard let self, let tab else { return }
            tab.onVideoMenu?(tab, state)
        }
    }
}

extension Browser {
    /// The menu itself, popped where the pointer already is — like the image
    /// one, the click that asked for this happened in JavaScript, with no
    /// native event left to hang an NSMenu off of.
    func showVideoMenu(for tab: Tab, state: VideoState) {
        guard let webView = tab.built else { return }
        let web = tab.web
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(MenuItem(state.paused ? "Play" : "Pause", image: state.paused ? "play.fill" : "pause.fill") {
            web.evaluateJavaScript(VideoRelay.act(tag: state.tag, "v.paused?v.play():v.pause()"), completionHandler: nil)
        })
        menu.addItem(MenuItem(state.muted ? "Unmute" : "Mute", image: state.muted ? "speaker.wave.2.fill" : "speaker.slash.fill") {
            web.evaluateJavaScript(VideoRelay.act(tag: state.tag, "v.muted=!v.muted"), completionHandler: nil)
        })
        let loop = MenuItem("Loop", image: "repeat") {
            web.evaluateJavaScript(VideoRelay.act(tag: state.tag, "v.loop=!v.loop"), completionHandler: nil)
        }
        loop.state = state.looped ? .on : .off
        menu.addItem(loop)
        menu.addItem(.separator())
        menu.addItem(MenuItem("Enter Full Screen", image: "arrow.up.left.and.arrow.down.right") {
            web.evaluateJavaScript(VideoRelay.act(tag: state.tag, "v.requestFullscreen?v.requestFullscreen():(v.webkitEnterFullscreen&&v.webkitEnterFullscreen())"), completionHandler: nil)
        })
        menu.addItem(MenuItem("Enter Picture in Picture", image: "pip.enter") {
            web.evaluateJavaScript(VideoRelay.act(tag: state.tag, "v.webkitSetPresentationMode&&v.webkitSetPresentationMode('picture-in-picture')"), completionHandler: nil)
        })
        menu.addItem(.separator())
        menu.addItem(MenuItem("Open Video in New Tab", image: "plus.square.on.square") { [weak self] in
            self?.open(state.url, foreground: true)
        })
        menu.addItem(MenuItem("Download Video", image: "arrow.down.to.line") { [weak self] in
            webView.startDownload(using: URLRequest(url: state.url)) { [weak self] download in
                self?.keep(download)
            }
        })
        menu.addItem(.separator())
        menu.addItem(MenuItem("Copy Video Address", image: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.url.absoluteString, forType: .string)
        })

        let screen = NSEvent.mouseLocation
        guard let window = webView.window else { return }
        let atWindow = window.convertPoint(fromScreen: screen)
        let atView = webView.convert(atWindow, from: nil)
        menu.popUp(positioning: nil, at: atView, in: webView)
    }
}
