import Foundation

final class SecureSettingsStore {
    static let shared = SecureSettingsStore()

    private let deepSeekAPIKeyKey = "sensen.deepseek.api.key"
    private let macSyncTokenKey = "sensen.mac.sync.token"

    private init() {}

    func deepSeekAPIKey() -> String? {
        UserDefaults.standard.string(forKey: deepSeekAPIKeyKey)
    }

    func saveDeepSeekAPIKey(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            UserDefaults.standard.removeObject(forKey: deepSeekAPIKeyKey)
        } else {
            UserDefaults.standard.set(key, forKey: deepSeekAPIKeyKey)
        }
    }

    func deleteDeepSeekAPIKey() throws {
        UserDefaults.standard.removeObject(forKey: deepSeekAPIKeyKey)
    }

    func macSyncToken() -> String? {
        UserDefaults.standard.string(forKey: macSyncTokenKey)
    }

    func saveMacSyncToken(_ value: String) throws {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            UserDefaults.standard.removeObject(forKey: macSyncTokenKey)
        } else {
            UserDefaults.standard.set(token, forKey: macSyncTokenKey)
        }
    }
}
