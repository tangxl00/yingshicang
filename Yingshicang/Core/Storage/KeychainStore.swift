import Foundation
import Security

/// 凭证存储（Keychain）。
///
/// 质检 P2 指出：WebDAV 密码属凭证类数据，写在 `UserDefaults` 里会随 App 沙箱备份/文件导出明文外泄。
/// 这里用 `kSecClassGenericPassword` 存一条通用凭据，service 固定、account 区分条目。
/// 读取失败（无记录/Keychain 不可用）统一返回空串，由界面提示用户重填，不做静默猜测。
enum KeychainStore {

    private static let service = "com.yingshicang.ios.credentials"

    /// 写入（已存在则先删后写，避免 `errSecDuplicateItem`）。
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        guard !account.isEmpty else { return false }
        let data = Data(value.utf8)
        remove(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Log.error("[Keychain] add \(account) failed: \(status)")
            return false
        }
        return true
    }

    /// 读取。没有记录返回空串。
    static func get(account: String) -> String {
        guard !account.isEmpty else { return "" }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    @discardableResult
    static func remove(account: String) -> Bool {
        guard !account.isEmpty else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
