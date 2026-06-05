import SwiftUI

@main
struct XiaodongwuYetanhuiApp: App {
    @StateObject private var store = CompanionStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
        }
    }
}
