import AppKit
import CoreImage
import Foundation
import UserNotifications
import WebKit

// "Make Web App" (Safari calls it Add to Dock): a site becomes its own copy
// of Satori.app — same binary, a different bundle id and an Info.plist entry
// naming its one site. The bundle id is what does the actual work: WebKit
// and UserDefaults both key their default stores off it, so a clone gets its
// own cookies, its own history, its own settings for free. This file is the
// switch that flips the rest of the app into "I am that clone" mode, plus
// the builder that makes one and the notification relay that only a web app
// needs.

enum WebApp {
    /// The one site this copy of the app is pinned to. Nil in the ordinary
    /// browser. Read once, from a key `build(from:into:)` below writes —
    /// nothing at runtime ever sets it.
    static let start: URL? = (Bundle.main.infoDictionary?["SatoriWebApp"] as? String).flatMap { URL(string: $0) }
    static var on: Bool { start != nil }
    static let name: String? = Bundle.main.infoDictionary?["SatoriWebAppName"] as? String
    static var host: String? { start?.host()?.lowercased() }

    /// example.com and accounts.example.com are the same site; a link to
    /// somewhere else opens in the main browser instead (see Browser's
    /// decidePolicyFor). Reuses Vault's eTLD+1, which already knows about
    /// bbc.co.uk-shaped endings.
    static func sameSite(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased(), let base = WebApp.host else { return true }
        return Vault.registrable(host) == Vault.registrable(base)
    }

    /// Held for as long as the process runs, so a hidden web-app window
    /// never gets App Napped away from the socket a push notification would
    /// arrive on. Losing the token would end the activity immediately, so it
    /// is kept in a static rather than a local.
    private static var activity: NSObjectProtocol?

    static func stayAlive() {
        guard on, activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Web app stays live for notifications"
        )
    }

    /// A link leaving the site, handed to whatever browser the Mac opens
    /// links with. The web app itself is never a candidate: its copy of the
    /// bundle declares no http scheme.
    static func openOutside(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - the builder (main Satori only)

    /// What the page itself says about its name and its icons — read once,
    /// off the page, before anything is downloaded.
    private static let sniff = #"""
    (function () {
      function meta(name) {
        var m = document.querySelector('meta[name="' + name + '"]');
        return m ? m.content : null;
      }
      var icons = [];
      document.querySelectorAll('link[rel~="apple-touch-icon"]').forEach(function (l) {
        icons.push({ href: l.href, sizes: l.getAttribute('sizes') || '', apple: true });
      });
      document.querySelectorAll('link[rel~="icon"]').forEach(function (l) {
        icons.push({ href: l.href, sizes: l.getAttribute('sizes') || '', apple: false });
      });
      var manifest = document.querySelector('link[rel="manifest"]');
      return {
        title: document.title || '',
        name: meta('application-name') || meta('apple-mobile-web-app-title') || null,
        manifest: manifest ? manifest.href : null,
        icons: icons,
      };
    })();
    """#

    /// A title's own suffix — " | Example", " – Example Co" — is the site's
    /// name repeated, not the page's; cut at the first of those separators
    /// when what's left still reads like a name.
    private static func trimTitle(_ title: String) -> String {
        for sep in [" | ", " · ", " — ", " – ", " - "] {
            if let range = title.range(of: sep) {
                let head = String(title[title.startIndex..<range.lowerBound])
                if head.count >= 3 { return head }
            }
        }
        return title
    }

    /// Entry point for File ▸ Make Web App…. Reads the page for a name and
    /// the best icon it offers, then asks before building anything.
    @MainActor
    static func make(from tab: Tab, browser: Browser) {
        guard let pageURL = tab.address else { return }
        tab.web.evaluateJavaScript(sniff) { result, _ in
            MainActor.assumeIsolated {
                let sniffed = result as? [String: Any] ?? [:]
                let title = (sniffed["title"] as? String) ?? ""
                let name = (sniffed["name"] as? String)?.trimmingCharacters(in: .whitespaces)
                    ?? (title.isEmpty ? (pageURL.host() ?? "Web App") : trimTitle(title))
                let icons = (sniffed["icons"] as? [[String: Any]]) ?? []
                let manifest = (sniffed["manifest"] as? String).flatMap { URL(string: $0) }
                presentAlert(suggested: name, pageURL: pageURL, icons: icons, manifest: manifest, browser: browser)
            }
        }
    }

    @MainActor
    private static func presentAlert(
        suggested name: String, pageURL: URL, icons: [[String: Any]], manifest: URL?, browser: Browser
    ) {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.contentView != nil }) else { return }
        let alert = NSAlert()
        alert.messageText = "Make Web App"
        alert.informativeText = "Creates a separate app for \(pageURL.host() ?? "this site"), with its own Dock icon, its own window, and its own sign-ins — kept apart from Satori's."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        // Read on the main actor, before the background hop below: the
        // fallback favicon is the only ingredient this builder needs that
        // Favicons only ever hands out on the main thread.
        let fallbackIcon = Favicons.shared.cached(pageURL.host()?.lowercased() ?? "")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let chosen = field.stringValue.trimmingCharacters(in: .whitespaces)
            let finalName = chosen.isEmpty ? name : chosen
            DispatchQueue.global(qos: .userInitiated).async {
                build(name: finalName, pageURL: pageURL, icons: icons, manifest: manifest, fallbackIcon: fallbackIcon, browser: browser)
            }
        }
    }

    // MARK: - fetching the best icon

    /// The manifest's own icons, if it has one, folded in beside the page's
    /// `<link>` candidates — largest first, apple-touch-icon (already square,
    /// already padded by whoever made the site) ahead of a plain favicon.
    private static func rankedIconURLs(_ icons: [[String: Any]], manifest: URL?, pageURL: URL) -> [(url: URL, apple: Bool)] {
        var candidates: [(url: URL, size: Int, apple: Bool)] = []
        for entry in icons {
            guard let href = entry["href"] as? String, let url = URL(string: href, relativeTo: pageURL)?.absoluteURL else { continue }
            let sizes = entry["sizes"] as? String ?? ""
            let size = sizes.split(separator: "x").first.flatMap { Int($0) } ?? 32
            candidates.append((url, size, entry["apple"] as? Bool ?? false))
        }
        if let manifest, let data = try? Data(contentsOf: manifest),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let manifestIcons = json["icons"] as? [[String: Any]] {
            for entry in manifestIcons {
                guard let src = entry["src"] as? String, let url = URL(string: src, relativeTo: manifest)?.absoluteURL else { continue }
                let sizes = entry["sizes"] as? String ?? ""
                let size = sizes.split(separator: "x").first.flatMap { Int($0) } ?? 192
                candidates.append((url, size, false))
            }
        }
        return candidates.sorted { $0.size > $1.size }.map { ($0.url, $0.apple) }
    }

    // MARK: - the actual build (off the main thread)

    private static func sanitize(_ host: String) -> String {
        String(host.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    /// Downloads the best icon it can find, composes the 1024×1024 macOS
    /// icon, clones the app, writes its plist, signs it, registers it with
    /// main Satori, and opens it. Announces the result either way. Runs off
    /// the main thread — cloning a ~40 MB bundle and shelling out to
    /// codesign and iconutil are not something a click should have to wait
    /// for synchronously.
    private static func build(
        name: String, pageURL: URL, icons: [[String: Any]], manifest: URL?, fallbackIcon: NSImage?, browser: Browser
    ) {
        guard let host = pageURL.host()?.lowercased() else {
            DispatchQueue.main.async { browser.announce("Couldn't tell which site this is") }
            return
        }
        let bundleID = "com.brandkit.satori.app.\(sanitize(host))"
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("\(name).app", isDirectory: true)

        let candidates = rankedIconURLs(icons, manifest: manifest, pageURL: pageURL)
        // An apple-touch-icon is drawn edge to edge already and only needs
        // the corners; anything smaller sits on a white tile.
        var made: NSImage?
        for (url, apple) in candidates {
            guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else { continue }
            made = apple ? clipToRoundedSquare(image) : composeIcon(site: image)
            break
        }

        do {
            let icon = made ?? composeIcon(site: fallbackIcon)
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            let icnsPath = scratch.appendingPathComponent("WebAppIcon.icns")
            try writeIcns(icon, to: icnsPath)

            try cloneAndPatch(
                bundleID: bundleID, name: name, startURL: pageURL, icns: icnsPath, destination: destination
            )

            var apps = registered
            if !apps.contains(destination.path) { apps.append(destination.path) }
            DispatchQueue.main.async {
                registered = apps
                NSWorkspace.shared.openApplication(at: destination, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    DispatchQueue.main.async {
                        browser.announce(error == nil ? "\(name) is in your Dock" : "Built \(name), but it wouldn't open")
                    }
                }
            }
        } catch {
            NSLog("WebApp.build failed: %@", "\(error)")
            DispatchQueue.main.async { browser.announce("Couldn't make a web app for \(host)") }
        }
    }

    /// macOS draws an app icon's body 824 across inside a 1024 canvas, with
    /// the rest left for its shadow — a tile filling all 1024 would stand
    /// larger than every other icon in the Dock.
    private static let tile = NSRect(x: 100, y: 100, width: 824, height: 824)

    /// A full-bleed apple-touch-icon already fills its square edge to edge —
    /// composing it onto another rounded square would double the corners.
    /// Clipped to the same shape `composeIcon` draws instead.
    private static func clipToRoundedSquare(_ image: NSImage) -> NSImage {
        let out = NSImage(size: NSSize(width: 1024, height: 1024))
        out.lockFocus()
        NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).addClip()
        image.draw(in: tile)
        out.unlockFocus()
        return out
    }

    /// The macOS-style icon every web app gets: a white rounded square, the
    /// site's own icon centered at 60% of it. No site icon at all still
    /// leaves a plain rounded square, closer to a blank Safari tile than to
    /// nothing.
    private static func composeIcon(site: NSImage?) -> NSImage {
        let canvas = NSImage(size: NSSize(width: 1024, height: 1024))
        canvas.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()
        if let site {
            site.draw(in: tile.insetBy(dx: tile.width * 0.2, dy: tile.height * 0.2))
        }
        canvas.unlockFocus()
        return canvas
    }

    /// iconutil wants a folder of specifically-named PNGs, not an .icns
    /// directly — an .iconset is the predictable, inspectable way there.
    private static func writeIcns(_ image: NSImage, to destination: URL) throws {
        let iconset = destination.deletingLastPathComponent().appendingPathComponent("WebAppIcon.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        let sizes: [(Int, String)] = [
            (16, "icon_16x16"), (32, "icon_16x16@2x"),
            (32, "icon_32x32"), (64, "icon_32x32@2x"),
            (128, "icon_128x128"), (256, "icon_128x128@2x"),
            (256, "icon_256x256"), (512, "icon_256x256@2x"),
            (512, "icon_512x512"), (1024, "icon_512x512@2x"),
        ]
        for (points, filename) in sizes {
            let resized = NSImage(size: NSSize(width: points, height: points))
            resized.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: NSRect(x: 0, y: 0, width: points, height: points))
            resized.unlockFocus()
            guard let resizedTiff = resized.tiffRepresentation, let resizedRep = NSBitmapImageRep(data: resizedTiff),
                  let png = resizedRep.representation(using: .png, properties: [:])
            else { continue }
            try png.write(to: iconset.appendingPathComponent("\(filename).png"))
        }
        try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", destination.path])
    }

    /// Exactly the recipe proven by hand in the shell before this was
    /// written: clone (an APFS copy-on-write clone, not a real copy),
    /// rewrite the plist, drop in the icon, strip the quarantine flag, and
    /// sign — never `--options runtime`: nothing here needs the hardened
    /// runtime, and it would ask for entitlements the copy doesn't carry.
    private static func cloneAndPatch(bundleID: String, name: String, startURL: URL, icns: URL, destination: URL) throws {
        let files = FileManager.default
        if files.fileExists(atPath: destination.path) {
            // Replacing in place keeps the bundle id, and with it the data
            // this same web app already has — nothing under Application
            // Support is touched here.
            try files.removeItem(at: destination)
        } else {
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try run("/bin/cp", ["-c", "-R", Bundle.main.bundlePath, destination.path])

        let plistURL = destination.appendingPathComponent("Contents/Info.plist")
        guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            throw NSError(domain: "WebApp", code: 2)
        }
        plist["CFBundleIdentifier"] = bundleID
        plist["CFBundleName"] = name
        plist["CFBundleDisplayName"] = name
        plist["SatoriWebApp"] = startURL.absoluteString
        plist["SatoriWebAppName"] = name
        plist["SatoriBuilt"] = stamp
        plist["CFBundleIconFile"] = "WebAppIcon"
        for key in ["CFBundleIconName", "CFBundleURLTypes", "CFBundleDocumentTypes",
                    "SUFeedURL", "SUEnableAutomaticChecks", "SUScheduledCheckInterval",
                    "SUAutomaticallyUpdate", "SUPublicEDKey"] {
            plist.removeValue(forKey: key)
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)

        try files.copyItem(at: icns, to: destination.appendingPathComponent("Contents/Resources/WebAppIcon.icns"))
        // The asset catalog still carries the old CFBundleIconName's icon
        // under macOS 26's Liquid Glass rendering, and would win over the
        // .icns even with the key gone from the plist.
        try? files.removeItem(at: destination.appendingPathComponent("Contents/Resources/Assets.car"))
        // Nor does a web app need what only the browser uses: Satori's own
        // icon, and Sparkle, which it never starts (it is linked weakly, see
        // Package.swift). Together that was half the copy.
        try? files.removeItem(at: destination.appendingPathComponent("Contents/Resources/AppIcon.icns"))
        try? files.removeItem(at: destination.appendingPathComponent("Contents/Frameworks/Sparkle.framework"))

        try run("/usr/bin/xattr", ["-cr", destination.path])
        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", signer, destination.path])
    }

    /// Who signs a web app: the Developer ID this Mac has, if it has one.
    /// macOS keys camera and microphone permission to a signature; an ad-hoc
    /// one changes with every rebuild, so every Satori update would have
    /// the web app asking again. A Developer ID keeps the same identity
    /// across rebuilds. Without one, ad hoc is what there is.
    // ponytail: most Macs have no Developer ID, so there it still re-asks;
    // a self-made signing certificate kept in the keychain would fix that.
    private static let signer: String = {
        let found = (try? run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"])) ?? ""
        guard let line = found.split(separator: "\n").first(where: { $0.contains("\"Developer ID Application:") }),
              let open = line.firstIndex(of: "\""), let close = line.lastIndex(of: "\""), open < close
        else { return "-" }
        return String(line[line.index(after: open)..<close])
    }()

    /// Which Satori a web app was cloned from: when its binary was written.
    /// The version number alone stays the same across every build in
    /// between releases, and a web app left on older code than the browser
    /// that made it is a bug waiting to be reported twice.
    private static var stamp: String {
        let binary = Bundle.main.executablePath ?? ""
        let date = (try? FileManager.default.attributesOfItem(atPath: binary)[.modificationDate]) as? Date
        return String(Int(date?.timeIntervalSince1970 ?? 0))
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "WebApp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\(launchPath) \(arguments.joined(separator: " ")): \(output)"])
        }
        return output
    }

    /// Run once, on main Satori's own launch: any web app it built that has
    /// fallen behind — a newer Satori shipped since — gets rebuilt from the
    /// running app, keeping its bundle id, its name, its site and its icon.
    /// A web app that's currently open is left alone rather than replaced
    /// out from under its own running process; a path whose bundle is gone
    /// is simply dropped from the list.
    static func refreshRegistered() {
        // Asked here, on the main thread: off it, the list of running apps
        // was never brought up to date, read as empty, and a web app was
        // rebuilt from under its own running process.
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        DispatchQueue.global(qos: .utility).async {
            var kept: [String] = []
            for path in registered {
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: path) else { continue }
                kept.append(path)
                guard let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                      let bundleID = plist["CFBundleIdentifier"] as? String,
                      let name = plist["CFBundleName"] as? String,
                      let startString = plist["SatoriWebApp"] as? String, let start = URL(string: startString)
                else { continue }
                guard plist["SatoriBuilt"] as? String != stamp else { continue }
                guard !running.contains(bundleID) else { continue }
                // The icon lives inside the bundle about to be replaced, so it
                // is taken out first — copied from where it was, it would be
                // gone by the time the new bundle asked for it.
                let icns = url.appendingPathComponent("Contents/Resources/WebAppIcon.icns")
                let kept = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).icns")
                guard (try? FileManager.default.copyItem(at: icns, to: kept)) != nil else { continue }
                try? cloneAndPatch(bundleID: bundleID, name: name, startURL: start, icns: kept, destination: url)
                try? FileManager.default.removeItem(at: kept)
            }
            if kept != registered { DispatchQueue.main.async { registered = kept } }
        }
    }

    // MARK: - registered web apps (main Satori only)

    /// Paths to the web apps this main Satori has built, so a launch can
    /// refresh any that have fallen behind. Never touched from inside a
    /// web app itself.
    static var registered: [String] {
        get { Store.settings.stringArray(forKey: "webApps") ?? [] }
        set { Store.settings.set(newValue, forKey: "webApps") }
    }
}

// MARK: - notifications (web-app mode only)

/// `window.Notification`, `ServiceWorkerRegistration.showNotification` and
/// `navigator.setAppBadge` all come through here from the page, and native
/// notifications come back the other way through `NotifyCenter`. Only wired
/// up in web-app mode: the main browser has no one site's notifications to
/// be, and no Dock badge that means anything for a hundred open tabs.
final class NotifyRelay: NSObject, WKScriptMessageHandlerWithReply {
    static let name = "satoriNotify"

    weak var tab: Tab?

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else {
            replyHandler(nil, "bad message")
            return
        }
        switch kind {
        case "ask":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                let answer = granted ? "granted" : "denied"
                Store.settings.set(answer, forKey: "notifications")
                DispatchQueue.main.async { replyHandler(answer, nil) }
            }
        case "show":
            let content = UNMutableNotificationContent()
            content.title = body["title"] as? String ?? WebApp.name ?? "Satori"
            if let text = body["body"] as? String { content.body = text }
            if body["silent"] as? Bool != true { content.sound = .default }
            let id = body["id"] as? String ?? UUID().uuidString
            let tag = body["tag"] as? String ?? ""
            let identifier = tag.isEmpty ? id : tag
            content.userInfo = ["id": id, "tab": tab?.id.uuidString ?? ""]
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { _ in
                DispatchQueue.main.async { replyHandler(nil, nil) }
            }
        case "close":
            let id = body["id"] as? String ?? ""
            let tag = body["tag"] as? String ?? ""
            let identifier = tag.isEmpty ? id : tag
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
            replyHandler(nil, nil)
        case "badge":
            let count = body["count"] as? Int
            switch count {
            case nil, .some(0): NSApp.dockTile.badgeLabel = nil
            case .some(-1): NSApp.dockTile.badgeLabel = "•"
            case .some(let n): NSApp.dockTile.badgeLabel = "\(n)"
            }
            replyHandler(nil, nil)
        default:
            replyHandler(nil, "unknown kind")
        }
    }

    /// The current permission, persisted the way Store.settings keeps
    /// everything else this app remembers between launches.
    static var permission: String {
        Store.settings.string(forKey: "notifications") ?? "default"
    }

    /// The shim replacing `window.Notification`. Interpolates the current
    /// permission so a page that checks `Notification.permission` before
    /// ever constructing one gets the right answer without a round trip.
    static func shim() -> String {
        let permission = Self.permission
        return #"""
        (function () {
          if (window.__satoriNotes) return;
          const post = (msg) => window.webkit.messageHandlers.satoriNotify.postMessage(msg);
          const live = new Map();

          class SatoriNotification extends EventTarget {
            static permission = "\#(permission)";
            static requestPermission(cb) {
              return post({ kind: "ask" }).then((answer) => {
                SatoriNotification.permission = answer;
                if (typeof cb === "function") cb(answer);
                return answer;
              });
            }
            constructor(title, options = {}) {
              super();
              this.title = title;
              this.body = options.body || "";
              this.tag = options.tag || "";
              this.data = options.data;
              this.icon = options.icon || "";
              this.silent = !!options.silent;
              this.id = String(Date.now()) + Math.random().toString(36).slice(2);
              this.onshow = null; this.onclick = null; this.onclose = null; this.onerror = null;
              live.set(this.id, this);
              if (SatoriNotification.permission !== "granted") {
                queueMicrotask(() => this._fire("error"));
                return;
              }
              post({ kind: "show", id: this.id, title, body: this.body, tag: this.tag, silent: this.silent })
                .then(() => this._fire("show"));
            }
            close() {
              post({ kind: "close", id: this.id, tag: this.tag });
              this._fire("close");
            }
            _fire(type) {
              const event = new Event(type);
              if (typeof this["on" + type] === "function") this["on" + type](event);
              this.dispatchEvent(event);
            }
          }

          window.__satoriNotes = {
            click(id) {
              const note = live.get(id);
              if (note) note._fire("click");
            },
          };
          window.Notification = SatoriNotification;

          if (window.ServiceWorkerRegistration) {
            window.ServiceWorkerRegistration.prototype.showNotification = function (title, options = {}) {
              new SatoriNotification(title, options);
              return Promise.resolve();
            };
            window.ServiceWorkerRegistration.prototype.getNotifications = function () {
              return Promise.resolve([]);
            };
          }
          if (navigator.permissions && navigator.permissions.query) {
            const query = navigator.permissions.query.bind(navigator.permissions);
            navigator.permissions.query = function (desc) {
              if (desc && desc.name === "notifications") {
                const state = SatoriNotification.permission === "default" ? "prompt" : SatoriNotification.permission;
                return Promise.resolve({ state, onchange: null });
              }
              return query(desc);
            };
          }
          navigator.setAppBadge = function (n) {
            post({ kind: "badge", count: typeof n === "number" ? n : -1 });
            return Promise.resolve();
          };
          navigator.clearAppBadge = function () {
            post({ kind: "badge", count: 0 });
            return Promise.resolve();
          };
        })();
        """#
    }
}

/// `willPresent` shows the banner even while the web app is frontmost —
/// otherwise a granted notification for the tab you're already looking at
/// never appears at all. `didReceive` brings the app forward and tells the
/// page which notification was clicked; only web-app windows install this,
/// so the main browser's own single delegate slot (there isn't one today)
/// is untouched.
final class WebAppNotifyDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Set once the browser exists, so a click can find its one tab.
    static weak var browser: Browser?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let id = info["id"] as? String ?? ""
        let tabID = (info["tab"] as? String).flatMap(UUID.init)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.contentView != nil }) {
                window.makeKeyAndOrderFront(nil)
            }
            if let tabID, let browser = WebAppNotifyDelegate.browser,
               let tab = browser.tabs.first(where: { $0.id == tabID }) {
                browser.select(tab)
                tab.web.evaluateJavaScript("window.__satoriNotes && window.__satoriNotes.click(\"\(id)\")")
            }
        }
        completionHandler()
    }
}

// MARK: - the bar's colour (web-app mode only)

extension Browser {
    /// A web app's bar wears the colour of the page's top edge as it is
    /// actually drawn. A site's named theme colour is often wrong for its own
    /// top (Telegram names white over a green wallpaper), and the page's
    /// styles can't see a picture or a canvas; its pixels can. The page says
    /// when something may have changed (see EdgeRelay); this once-a-second
    /// read is only for what it can't see coming — a wallpaper loading in.
    func watchEdge() {
        guard WebApp.on else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.active?.readEdge() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
    }
}

extension Tab {
    /// Something on the page moved. A press or a key usually starts what
    /// changes the top, so the edge is followed closely for a little while
    /// after. Anything else — the document changing — is read at once and
    /// once more a moment later.
    func edgeChanged(pressed: Bool) {
        edgeTrail.forEach { $0.cancel() }
        // A change to the document is read straight away too: an overlay
        // is put in at the start of its fade, and the page has its final
        // look from that moment — only the compositor is still easing to it.
        let delays: [Double] = pressed ? stride(from: 0, through: 0.6, by: 0.05).map { $0 } : [0, 0.15]
        edgeTrail = delays.map { delay in
            let work = DispatchWorkItem { [weak self] in self?.readEdge() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    /// One read at a time, twenty a second at most.
    func readEdge() {
        let now = CACurrentMediaTime()
        guard !edgeBusy, now - edgeLast >= 0.045, let web = built, web.window?.occlusionState.contains(.visible) == true,
              web.bounds.width > 0
        else { return }
        edgeBusy = true
        edgeLast = now
        let shot = WKSnapshotConfiguration()
        shot.rect = CGRect(x: 0, y: 0, width: web.bounds.width, height: 4)
        shot.snapshotWidth = 64
        shot.afterScreenUpdates = false
        web.takeSnapshot(with: shot) { [weak self] image, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.edgeBusy = false
                guard let image, let tint = WebApp.average(image) else { return }
                self.wear(tint)
            }
        }
    }
}

/// The page's word that its top may look different now: a press, a key, a
/// transition or an animation ending, the document changing. At most once a
/// frame. Web-app mode only.
final class EdgeRelay: NSObject, WKScriptMessageHandler {
    static let name = "satoriEdge"

    weak var tab: Tab?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let pressed = (message.body as? Int) == 1
        MainActor.assumeIsolated { tab?.edgeChanged(pressed: pressed) }
    }

    static let watch = """
    (function () {
      if (window.__satoriEdge) return;
      window.__satoriEdge = true;
      var waiting = false;
      function say() {
        if (waiting) return;
        waiting = true;
        requestAnimationFrame(function () {
          waiting = false;
          window.webkit.messageHandlers.\(name).postMessage(0);
        });
      }
      function pressed() { window.webkit.messageHandlers.\(name).postMessage(1); }
      ['pointerdown', 'pointerup', 'keydown'].forEach(function (n) {
        document.addEventListener(n, pressed, { capture: true, passive: true });
      });
      ['transitionend', 'animationend', 'scroll'].forEach(function (n) {
        document.addEventListener(n, say, { capture: true, passive: true });
      });
      new MutationObserver(say).observe(document.documentElement,
        { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'style'] });
    })();
    """
}

extension WebApp {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// The mean colour of a picture, as the bar would wear it.
    static func average(_ image: NSImage) -> Tint? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return Tint(bytes: Double(pixel[0]), g: Double(pixel[1]), b: Double(pixel[2]))
    }
}
