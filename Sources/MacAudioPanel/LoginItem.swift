import Observation
import ServiceManagement

/// "Launch at login" via SMAppService. macOS stores the setting itself, so
/// this always reads the live status rather than keeping its own copy.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var errorMessage: String?

    init() { reload() }

    func reload() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't change launch at login: \(error.localizedDescription)"
        }
        reload()
        if enabled, SMAppService.mainApp.status == .requiresApproval {
            errorMessage = "Approve Mac Audio Panel in System Settings > General > Login Items."
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
