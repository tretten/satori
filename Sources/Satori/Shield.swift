import WebKit

// The ad blocker. No settings, no counter, no shield icon going green — it is
// compiled once at launch and then it is simply true that the page is lighter.
//
// A content rule list is enforced inside WebKit's networking, before a request
// is made and before a stylesheet is applied, so this costs nothing at run time
// in the way a JavaScript blocker does.

@MainActor
final class Shield: ObservableObject {
    static let shared = Shield()

    private(set) var list: WKContentRuleList?
    private var waiting: [WKUserContentController] = []

    /// Set the one time compiling the list didn't work. The toggle in
    /// Settings can say "on" all it wants; nothing is actually blocked until
    /// this is nil, so it is the one thing worth telling a person about
    /// rather than failing the quiet way a missing ad is quiet.
    @Published private(set) var trouble: String?

    /// On unless somebody said otherwise. Every tab's controller is told when
    /// this changes, so it takes effect on the next request rather than the
    /// next launch.
    var enabled = true

    /// Sites it is off for — the ones it broke. A checkout that never
    /// finishes, a video that never starts: switching off here, for this site,
    /// beats switching off everywhere and forgetting to switch back.
    private(set) var paused: Set<String> = Set(
        Store.settings.stringArray(forKey: "shield.paused") ?? []
    )

    func isPaused(on host: String?) -> Bool {
        guard let host else { return false }
        return paused.contains(host)
    }

    func pause(_ host: String, _ off: Bool) {
        if off { paused.insert(host) } else { paused.remove(host) }
        Store.settings.set(Array(paused).sorted(), forKey: "shield.paused")
    }

    /// Before each page: the list goes on or off for the site this tab is
    /// heading to. A rule list is enforced from the moment it is added, so
    /// doing this at the navigation is what makes "off for this site" true
    /// for the whole page rather than for the second half of it.
    func tune(_ controller: WKUserContentController, for host: String?) {
        guard let list else { return }
        controller.remove(list)
        if enabled, !isPaused(on: host) { controller.add(list) }
    }

    /// Third parties whose only job is to watch or to sell. First-party
    /// requests are untouched: a site's own scripts are the site.
    private static let unwanted = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "googletagservices.com", "google-analytics.com", "googletagmanager.com",
        "adservice.google.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org",
        "criteo.com", "criteo.net", "taboola.com", "outbrain.com",
        "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com",
        "smartadserver.com", "sharethrough.com", "indexww.com", "bidswitch.net",
        "33across.com", "teads.tv", "moatads.com", "adroll.com",
        "scorecardresearch.com", "quantserve.com", "chartbeat.com",
        "hotjar.com", "mouseflow.com", "fullstory.com", "clarity.ms",
        "mixpanel.com", "amplitude.com", "segment.com", "segment.io",
        "branch.io", "appsflyer.com", "adjust.com", "analytics.tiktok.com",
        "connect.facebook.net", "ads-twitter.com", "analytics.twitter.com",
    ]

    /// The few slots that are reliably an advertisement and nothing else. Kept
    /// deliberately short — a generous cosmetic list is how a blocker starts
    /// eating the page it was meant to clean.
    private static let slots = [
        ".adsbygoogle", "ins.adsbygoogle", "[id^=\"google_ads_\"]",
        "[id^=\"div-gpt-ad\"]", "[id^=\"taboola-\"]", "#taboola-below-article",
        "iframe[src*=\"doubleclick.net\"]", "iframe[src*=\"googlesyndication\"]",
        "iframe[src*=\"amazon-adsystem\"]",
    ]

    func compile() {
        guard list == nil else { return }
        trouble = nil
        var rules: [[String: Any]] = Shield.unwanted.map { domain in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            return [
                "trigger": [
                    "url-filter": "^https?://([^/]+\\.)?\(escaped)",
                    "load-type": ["third-party"],
                ],
                "action": ["type": "block"],
            ]
        }
        rules.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": Shield.slots.joined(separator: ", ")],
        ])

        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8)
        else {
            trouble = "Could not build the block list"
            return
        }

        guard let store = WKContentRuleListStore.default() else {
            trouble = "WebKit has nowhere to compile it"
            return
        }
        store.compileContentRuleList(
            forIdentifier: "office-shield",
            encodedContentRuleList: json
        ) { [weak self] compiled, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let compiled else {
                    self.trouble = error?.localizedDescription ?? "Compiling the block list failed"
                    return
                }
                self.list = compiled
                // Tabs that opened while this was still compiling get it now.
                if self.enabled { self.waiting.forEach { $0.add(compiled) } }
                self.waiting = []
            }
        }
    }

    /// Every tab asks for it; whoever asks before it is ready is remembered.
    func protect(_ controller: WKUserContentController) {
        if let list {
            if enabled { controller.add(list) }
        } else {
            waiting.append(controller)
        }
    }

    /// Switched on or off for every page that is already open.
    func apply(to controllers: [WKUserContentController]) {
        guard let list else { return }
        for controller in controllers {
            controller.remove(list)
            if enabled { controller.add(list) }
        }
    }
}

extension Shield {
    /// Google's "Switch to Chrome?" — on its search, Gmail, YouTube and the
    /// Web Store, to anyone not in Chrome, Safari included. Not the site
    /// refusing the browser, only Google asking; answered "No thanks" where
    /// there is such a button, so Google remembers, and otherwise taken off
    /// the screen. Found by what it says, since its markup changes weekly —
    /// the sentence doesn't. Google's own sites only, and at most once a
    /// second: Gmail changes its page all the time.
    static let nudges = """
    (function () {
      if (window.__satoriNudges || window.top !== window) return;
      if (!/(^|\\.)(google\\.[a-z.]+|youtube\\.com|gmail\\.com)$/.test(location.hostname)) return;
      window.__satoriNudges = true;
      var said = /switch to chrome|google recommends using chrome|try (google )?chrome|get (google )?chrome|use chrome|download chrome|перейти на chrome|попробуйте (google )?chrome|скачайте chrome|google рекомендует/i;
      var no = /^(no,? thanks|not now|no thanks|dismiss|close|нет,? спасибо|не сейчас|закрыть)$/i;
      function box(el) {
        for (var n = el, i = 0; n && n !== document.body && i < 12; n = n.parentElement, i++) {
          var role = n.getAttribute && n.getAttribute('role');
          if (role === 'dialog' || role === 'alertdialog' || n.getAttribute('aria-modal') === 'true') return n;
          var pos = getComputedStyle(n).position;
          if (pos === 'fixed' || pos === 'sticky') return n;
        }
        return null;
      }
      function sweep() {
        var found = document.evaluate("//*[contains(text(),'Chrome')]", document.body || document, null,
          XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
        for (var i = 0; i < found.snapshotLength; i++) {
          var el = found.snapshotItem(i);
          if (!said.test(el.textContent || '') || el.closest('[data-satori-nudge]')) continue;
          var b = box(el);
          if (!b) continue;
          b.setAttribute('data-satori-nudge', '');
          var buttons = b.querySelectorAll('button, [role=button], a');
          var answered = false;
          for (var j = 0; j < buttons.length; j++) {
            var label = (buttons[j].textContent || buttons[j].getAttribute('aria-label') || '').trim();
            if (no.test(label)) { buttons[j].click(); answered = true; break; }
          }
          if (!answered) b.style.setProperty('display', 'none', 'important');
        }
      }
      var last = 0, queued = false;
      function soon() {
        if (queued) return;
        queued = true;
        setTimeout(function () { queued = false; last = Date.now(); sweep(); }, Math.max(0, 1000 - (Date.now() - last)));
      }
      new MutationObserver(soon).observe(document.documentElement, { childList: true, subtree: true });
      soon();
    })();
    """
}

