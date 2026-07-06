import SwiftUI

@main
struct FocusBrowserApp: App {
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(model)
        } label: {
            Image(systemName: "moon.circle")
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        AppModel.shared.startMonitoring()
    }
}
