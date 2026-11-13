import SwiftUI

@main
struct MacAudioPanelApp: App {
    @State private var model = AppListModel()
    @State private var loginItem = LoginItem()

    var body: some Scene {
        MenuBarExtra("Mac Audio Panel", systemImage: "speaker.wave.2.fill") {
            PanelView(model: model, loginItem: loginItem)
        }
        .menuBarExtraStyle(.window)
    }
}
