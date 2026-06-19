import SwiftUI

@main
struct XiaodongwuYetanhuiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = CompanionStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await store.syncAllFromBackend()
            }
        }
    }
}
