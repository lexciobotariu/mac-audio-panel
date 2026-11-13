import SwiftUI

struct PanelView: View {
    @Bindable var model: AppListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppsCard(model: model)
            HStack {
                Spacer()
                Button("Quit Mac Audio Panel") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 320)
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
                    AppRow(app: app) { model.toggleMute(app.id) }
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
