import Foundation

/// Remembers which apps the user muted, by bundle ID, plus a display name so a
/// muted app can still be listed (and unmuted) while it is not running.
struct SettingsStore {
    private let defaults: UserDefaults
    private let mutedKey = "mutedApps"
    private let favoritesKey = "favoriteApps"
    private let onboardingKey = "hasSeenOnboarding"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Bundle ID -> app name at the time it was muted.
    var mutedApps: [String: String] {
        get { defaults.dictionary(forKey: mutedKey) as? [String: String] ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: mutedKey) }
    }

    /// Bundle IDs the user starred; pinned to the top of the list.
    var favoriteApps: Set<String> {
        get { Set(defaults.stringArray(forKey: favoritesKey) ?? []) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: favoritesKey) }
    }

    var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: onboardingKey) }
        nonmutating set { defaults.set(newValue, forKey: onboardingKey) }
    }
}
