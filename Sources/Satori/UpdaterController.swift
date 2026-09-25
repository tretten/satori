import AppKit
import Sparkle

// Knowing when there is a newer one, and having it ready.
//
// Sparkle 2 does the work the hand-rolled updater used to: a background check
// shortly after launch plus a daily scheduled check (SUScheduledCheckInterval).
// "Check for Updates…" triggers a foreground check. Downloaded updates install
// silently on quit (SUAutomaticallyUpdate) — no forced restart mid-session,
// so a page being read is never interrupted by a browser that wants to be newer.
//
// The feed (SUFeedURL) and the EdDSA public key (SUPublicEDKey) live in the
// generated Info.plist — see build.sh. The private half stays in the login
// keychain under the `satori` account and never ships with the app.
@MainActor
final class UpdaterController: NSObject, SPUUpdaterDelegate {
    static let shared = UpdaterController()
    private static let noUpdateErrorCode = 1001
    private static let installationCanceledErrorCode = 4007
    private static let installationAuthorizeLaterErrorCode = 4008

    /// The UserDefaults key behind the Settings › About toggle. Absent in old
    /// files means on, like every other default that used to be quiet.
    static let automaticChecksKey = "updates.automatic"

    static var automaticallyChecksForUpdates: Bool {
        Store.settings.object(forKey: automaticChecksKey) as? Bool ?? true
    }

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        // startingUpdater: true boots the updater with the app (incl. scheduled checks).
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: nil)
        setAutomaticallyChecksForUpdates(Self.automaticallyChecksForUpdates)
        // The scheduled interval counts from the last check: a release shipped
        // after it would otherwise wait a full day post-relaunch. So check once
        // in the background on every launch; a found update downloads silently
        // and installs on quit — nothing to ask about.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, Self.automaticallyChecksForUpdates else { return }
            self.controller.updater.checkForUpdatesInBackground()
        }
    }

    /// Toggles Sparkle background/scheduled checks live; manual
    /// "Check for Updates…" keeps working either way.
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    /// Wired to the "Check for Updates…" menu command and the About pane button.
    @objc func checkForUpdates(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(sender)
    }

    /// A failed download/verify/install cycle must not wedge the scheduler —
    /// reset it so the next auto or manual check runs cleanly. Cancellation
    /// and "already up to date" are not errors.
    func updater(_ updater: SPUUpdater,
                 didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                 error: Error?) {
        guard let nsError = error as NSError?,
              nsError.domain == SUSparkleErrorDomain,
              nsError.code != Self.noUpdateErrorCode,
              nsError.code != Self.installationCanceledErrorCode,
              nsError.code != Self.installationAuthorizeLaterErrorCode
        else { return }

        NSLog("Sparkle update failed; scheduling a fresh update cycle: %@", nsError)
        updater.resetUpdateCycleAfterShortDelay()
    }
}
