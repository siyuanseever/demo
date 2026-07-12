import SwiftUI

@main
struct XiaodongwuYetanhuiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = CompanionStore()
    @StateObject private var speech = SpeechService()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .environmentObject(speech)
                .task {
                    await store.loadStarMapInsightIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await store.syncIfNeeded()
                await store.loadStarMapInsightIfNeeded()
            }
        }
    }
}
