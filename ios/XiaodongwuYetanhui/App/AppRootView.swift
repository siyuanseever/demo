import SwiftUI

struct AppRootView: View {
    @State private var selectedTab: AppTab = .chat

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    tab.content {
                        selectedTab = .chat
                    }
                }
                .tabItem { tab.label }
                .tag(tab)
            }
        }
        .tint(Color.warmBrown)
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case chat
    case state
    case memory
    case companions
    case settings

    var id: String { rawValue }

    @ViewBuilder
    func content(openChat: @escaping () -> Void) -> some View {
        switch self {
        case .chat:
            ChatView()
        case .state:
            StateOverviewView(openChat: openChat)
        case .memory:
            MemoryListView()
        case .companions:
            CompanionGardenView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .chat:
            Label("夜谈", systemImage: "bubble.left.and.bubble.right.fill")
        case .state:
            Label("状态", systemImage: "heart.text.square.fill")
        case .memory:
            Label("记忆", systemImage: "leaf.fill")
        case .companions:
            Label("小动物", systemImage: "pawprint.fill")
        case .settings:
            Label("设置", systemImage: "slider.horizontal.3")
        }
    }
}
