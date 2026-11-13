import SwiftUI

struct PanelView: View {
    @Bindable var model: AppListModel
    @Bindable var loginItem: LoginItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.showOnboarding {
                OnboardingCard(model: model)
            }
            if let message = model.errorMessage ?? loginItem.errorMessage {
                ErrorBanner(message: message) {
                    model.dismissError()
                    model.openPrivacySettings()
                }
            }
            AppsCard(model: model)
            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { loginItem.reload() }
    }
}

/// First-run explanation of the one permission the app needs.
struct OnboardingCard: View {
    let model: AppListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("One permission needed", systemImage: "hand.raised.fill")
                .font(.headline)
            Text("To mute an app, Mac Audio Panel taps that app's sound and throws it away. macOS calls this System Audio Recording and asks once, the first time you mute something. Nothing is recorded or saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Privacy Settings") { model.openPrivacySettings() }
                Spacer()
                Button("Got it") { model.dismissOnboarding() }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
    }
}

struct ErrorBanner: View {
    let message: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings", action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }
}

/// The "Apps" card from the design: header, playing count, Show All, rows.
struct AppsCard: View {
    @Bindable var model: AppListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apps").font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.showAll ? "Show Playing" : "Show All") {
                    model.showAll.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.bottom, 8)

            let apps = model.visibleApps
            if apps.isEmpty {
                Text(model.showAll ? "No apps are using audio." : "Nothing is playing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(apps) { app in
                    AppRow(
                        app: app,
                        toggleMute: { model.toggleMute(app.id) },
                        toggleFavorite: { model.toggleFavorite(app.id) }
                    )
                    if app.id != apps.last?.id { Divider() }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }

    private var subtitle: String {
        let count = model.playingCount
        return count == 1 ? "1 App Playing" : "\(count) Apps Playing"
    }
}

struct AppRow: View {
    let app: AppEntry
    let toggleMute: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 24, height: 24)
            Text(app.name).lineLimit(1)
            if app.isMuted {
                Badge(text: "Muted", color: .red)
            } else if app.isPlaying {
                Badge(text: "Playing", color: .accentColor)
            }
            Spacer()
            Button(action: toggleFavorite) {
                Image(systemName: app.isFavorite ? "star.fill" : "star")
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(app.isFavorite ? Color.yellow : Color.secondary)
            .help(app.isFavorite ? "Unpin \(app.name)" : "Pin \(app.name) to the top")
            Button(action: toggleMute) {
                Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(app.isMuted ? Color.red : Color.secondary)
            .help(app.isMuted ? "Unmute \(app.name)" : "Mute \(app.name)")
        }
        .padding(.vertical, 6)
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}
