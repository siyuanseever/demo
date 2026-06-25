import Foundation
import Security

final class SecureSettingsStore {
    static let shared = SecureSettingsStore()

    private let service = "com.sensen.story.credentials"
    private let deepSeekAPIKeyAccount = "deepseek-api-key"
    private let macSyncTokenAccount = "mac-sync-token"

    private init() {}

    func deepSeekAPIKey() -> String? {
        read(account: deepSeekAPIKeyAccount)
    }

    func saveDeepSeekAPIKey(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            try delete(account: deepSeekAPIKeyAccount)
            return
        }
        try write(key, account: deepSeekAPIKeyAccount)
    }

    func deleteDeepSeekAPIKey() throws {
        try delete(account: deepSeekAPIKeyAccount)
    }

    func macSyncToken() -> String? {
        read(account: macSyncTokenAccount)
    }

    func saveMacSyncToken(_ value: String) throws {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            try delete(account: macSyncTokenAccount)
        } else {
            try write(token, account: macSyncTokenAccount)
        }
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SecureSettingsError.keychain(updateStatus)
        }
        var insert = query
        attributes.forEach { insert[$0.key] = $0.value }
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw SecureSettingsError.keychain(insertStatus)
        }
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureSettingsError.keychain(status)
        }
    }
}

enum SecureSettingsError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "无法访问系统钥匙串（\(status)）"
        }
    }
}
