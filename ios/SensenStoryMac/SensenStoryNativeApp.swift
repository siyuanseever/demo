import SwiftUI

@main
struct SensenStoryNativeApp: App {
    @StateObject private var store = NativeMacShellStore()
    @StateObject private var speech = SpeechService()

    var body: some Scene {
        WindowGroup("森森物语") {
            NativeMacRootView()
                .environmentObject(store)
                .environmentObject(speech)
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
                    .disabled(
                        store.isSending
                            || store.selectedSessionID == nil
                            || store.messages.allSatisfy { $0.role != .user }
                    )
            }

            SidebarCommands()
        }

        Settings {
            NativeMacSettingsView()
                .environmentObject(store)
                .environmentObject(speech)
                .frame(width: 560, height: 500)
        }
    }
}

extension Notification.Name {
    static let nativeOpenConversation = Notification.Name("sensen.native.openConversation")
    static let nativeOpenFlow = Notification.Name("sensen.native.openFlow")
}
