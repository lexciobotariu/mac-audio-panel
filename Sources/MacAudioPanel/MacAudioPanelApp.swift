import SwiftUI

@main
struct MacAudioPanelApp: App {
    @State private var model = AppListModel()

    var body: some Scene {
        MenuBarExtra("Mac Audio Panel", systemImage: "speaker.wave.2.fill") {
            PanelView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
