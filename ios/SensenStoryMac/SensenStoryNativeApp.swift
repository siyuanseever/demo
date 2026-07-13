import SwiftUI

@main
struct SensenStoryNativeApp: App {
    @StateObject private var store = NativeMacShellStore()

    var body: some Scene {
        WindowGroup("森森物语") {
            NativeMacRootView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新夜谈") {
                    store.newConversation()
                    NotificationCenter.default.post(name: .nativeOpenConversation, object: nil)
                }
                .keyboardShortcut("n")
            }

            CommandMenu("夜谈") {
                Button("结束并总结") {
                    Task { await store.closeCurrentSession() }
                }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.isSending || store.messages.allSatisfy { $0.role != .user })
            }

            SidebarCommands()
        }

        Settings {
            NativeMacSettingsView()
                .environmentObject(store)
                .frame(width: 560, height: 360)
        }
    }
}

extension Notification.Name {
    static let nativeOpenConversation = Notification.Name("sensen.native.openConversation")
}
