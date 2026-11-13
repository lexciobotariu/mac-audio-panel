import Foundation

/// Remembers which apps the user muted, by bundle ID, plus a display name so a
/// muted app can still be listed (and unmuted) while it is not running.
struct SettingsStore {
    private let defaults: UserDefaults
    private let mutedKey = "mutedApps"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Bundle ID -> app name at the time it was muted.
    var mutedApps: [String: String] {
        get { defaults.dictionary(forKey: mutedKey) as? [String: String] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: mutedKey) }
    }
}
