import Combine
import Foundation

@MainActor
final class NativeMacShellStore: ObservableObject {
    @Published private(set) var snapshot = DashboardSnapshot(
        sessionCount: 0,
        messageCount: 0,
        memoryCount: 0,
        journalCount: 0
    )
    @Published private(set) var databasePath = "尚未打开本地缓存"
    @Published private(set) var databaseError: String?
    @Published private(set) var backendStatus = BackendConnectionStatus(
        state: .unknown,
        baseURL: "http://127.0.0.1:8765",
        detail: "尚未检查本机后端。",
        lastCheckedAt: nil
    )
    @Published private(set) var isCheckingBackend = false

    private let chatService = ChatService()

    init() {
        loadLocalCache()
    }

    func loadLocalCache() {
        do {
            let database = try SQLiteDatabase()
            databasePath = database.path
            snapshot = DashboardSnapshot(
                sessionCount: database.count(table: "sessions"),
                messageCount: database.count(table: "messages"),
                memoryCount: database.count(table: "memories"),
                journalCount: database.count(table: "journals")
            )
            databaseError = nil
        } catch {
            databaseError = error.localizedDescription
        }
    }

    func checkBackend() async {
        guard !isCheckingBackend else { return }
        isCheckingBackend = true
        backendStatus = await chatService.checkConnection()
        isCheckingBackend = false
    }
}
