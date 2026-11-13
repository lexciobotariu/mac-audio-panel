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
            MainActor.assumeIsolated { self?.unmuteAll() }
        }
        refresh()
    }

    func toggleMute(_ bundleID: String) {
        if let muter = muters.removeValue(forKey: bundleID) {
            muter.stop()
        } else {
            let muter = Muter(target: bundleID, mode: .mutedWithReader)
            do {
                try muter.start()
                muters[bundleID] = muter
            } catch {
                log("could not mute \(bundleID): \(error)")
            }
        }
        refresh()
    }

    func unmuteAll() {
        muters.values.forEach { $0.stop() }
        muters.removeAll()
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
