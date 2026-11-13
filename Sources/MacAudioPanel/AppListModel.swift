import AppKit
import AudioCore
import CoreAudio
import Observation

/// One row in the Apps list: a user-facing app and all its audio processes.
struct AppEntry: Identifiable, Equatable {
    /// Bundle ID of the user-facing app (helpers are folded into it).
    let id: String
    let name: String
    let icon: NSImage
    var isPlaying: Bool
    var isMuted: Bool
}

@MainActor
@Observable
final class AppListModel {
    private(set) var apps: [AppEntry] = []
    var showAll = false

    /// Playing or muted apps, or every app using audio when Show All is on.
    var visibleApps: [AppEntry] {
        showAll ? apps : apps.filter { $0.isPlaying || $0.isMuted }
    }

    var playingCount: Int { apps.filter { $0.isPlaying && !$0.isMuted }.count }

    @ObservationIgnored private var muters: [String: Muter] = [:]
    @ObservationIgnored private var appInfo: [String: (name: String, icon: NSImage)] = [:]
    @ObservationIgnored private var processListener: PropertyListener?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private let ownBundleID = Bundle.main.bundleIdentifier
    @ObservationIgnored private let settings = SettingsStore()

    init() {
        processListener = try? onSystemChange(kAudioHardwarePropertyProcessObjectList, queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Playing state has no cheap system-wide notification; poll it.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAllMuters() }
        }
        // Taps and aggregate devices may not survive sleep; rebuild on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.muters.values.forEach { $0.rebuild() } }
        }

        // Re-apply saved mutes. A muter for an app that is not running simply
        // waits and mutes it the moment it starts using audio.
        for (bundleID, name) in settings.mutedApps {
            rememberInfo(for: bundleID, fallbackName: name)
            startMuter(for: bundleID)
        }
        refresh()
    }

    func toggleMute(_ bundleID: String) {
        var saved = settings.mutedApps
        if let muter = muters.removeValue(forKey: bundleID) {
            muter.stop()
            saved[bundleID] = nil
        } else if startMuter(for: bundleID) {
            saved[bundleID] = appInfo[bundleID]?.name ?? bundleID
        }
        settings.mutedApps = saved
        refresh()
    }

    @discardableResult
    private func startMuter(for bundleID: String) -> Bool {
        let muter = Muter(target: bundleID, mode: .mutedWithReader)
        do {
            try muter.start()
            muters[bundleID] = muter
            return true
        } catch {
            log("could not mute \(bundleID): \(error)")
            return false
        }
    }

    /// Stops tapping on quit. Saved mutes are kept and re-applied next launch.
    private func stopAllMuters() {
        muters.values.forEach { $0.stop() }
        muters.removeAll()
    }

    /// Name and icon for an app that may not be running, from its installed bundle.
    private func rememberInfo(for bundleID: String, fallbackName: String) {
        guard appInfo[bundleID] == nil else { return }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            appInfo[bundleID] = (name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        } else {
            appInfo[bundleID] = (name: fallbackName, icon: NSWorkspace.shared.icon(for: .application))
        }
    }

    func refresh() {
        guard let processes = try? listAudioProcesses() else { return }

        // Fold every audio process into the app the user would recognise.
        var playing: [String: Bool] = [:]
        for process in processes {
            guard let raw = process.appBundleID,
                  let bundleID = resolveApp(raw),
                  bundleID != ownBundleID
            else { continue }
            playing[bundleID] = (playing[bundleID] ?? false) || process.isRunningOutput
        }
        // Muted apps stay listed even while they have no audio process.
        for bundleID in muters.keys where playing[bundleID] == nil && appInfo[bundleID] != nil {
            playing[bundleID] = false
        }

        let entries = playing.compactMap { bundleID, isPlaying -> AppEntry? in
            guard let info = appInfo[bundleID] else { return nil }
            return AppEntry(
                id: bundleID,
                name: info.name,
                icon: info.icon,
                isPlaying: isPlaying,
                isMuted: muters[bundleID] != nil
            )
        }
        .sorted {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        if entries != apps { apps = entries }
    }

    /// Maps a process's bundle ID to a running, user-facing app, trying parent
    /// IDs for helpers (com.google.Chrome.helper -> com.google.Chrome).
    /// Background daemons with no regular app resolve to nil and are hidden.
    private func resolveApp(_ bundleID: String) -> String? {
        var parts = bundleID.split(separator: ".").map(String.init)
        while parts.count >= 2 {
            let candidate = parts.joined(separator: ".")
            if appInfo[candidate] != nil { return candidate }
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: candidate)
                .first(where: { $0.activationPolicy == .regular }) {
                appInfo[candidate] = (
                    name: app.localizedName ?? candidate,
                    icon: app.icon ?? NSWorkspace.shared.icon(for: .application)
                )
                return candidate
            }
            parts.removeLast()
        }
        return nil
    }
}
