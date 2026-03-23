import Foundation
import Security

private enum SubscriptionCloudMirrorStore {
    private static let store = NSUbiquitousKeyValueStore.default

    static func string(forKey key: String) -> String? {
        _ = store.synchronize()
        let value = store.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    static func data(forKey key: String) -> Data? {
        _ = store.synchronize()
        return store.data(forKey: key)
    }

    static func set(_ value: String, forKey key: String) {
        store.set(value, forKey: key)
        _ = store.synchronize()
    }

    static func set(_ data: Data, forKey key: String) {
        store.set(data, forKey: key)
        _ = store.synchronize()
    }
}

final class SubscriptionIdentityStore {
    static let shared = SubscriptionIdentityStore()

    private let service = Bundle.main.bundleIdentifier ?? "tw.yian.CogniSphere"
    private let account = "subscription.appUserID"
    private let cloudAccount = "subscription.appUserID.cloud"

    private init() {}

    var appUserID: String {
        if let cloudValue = SubscriptionCloudMirrorStore.string(forKey: cloudAccount) {
            if readValue() != cloudValue {
                writeValue(cloudValue)
            }
            return cloudValue
        }

        if let existing = readValue() {
            SubscriptionCloudMirrorStore.set(existing, forKey: cloudAccount)
            return existing
        }

        let generated = "cognisphere-\(UUID().uuidString.lowercased())"
        writeValue(generated)
        SubscriptionCloudMirrorStore.set(generated, forKey: cloudAccount)
        return generated
    }

    private func readValue() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private func writeValue(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }
}

struct SubscriptionQuotaState: Codable {
    let dayStart: TimeInterval
    let usedCount: Int
}

final class SubscriptionQuotaStore {
    static let shared = SubscriptionQuotaStore()

    private let service = Bundle.main.bundleIdentifier ?? "tw.yian.CogniSphere"
    private let account = "subscription.quotaState"
    private let cloudAccount = "subscription.quotaState.cloud"

    private init() {}

    func loadState() -> SubscriptionQuotaState? {
        let local = readLocalState()
        let cloud = readCloudState()
        let merged = mergedState(local: local, cloud: cloud)
        guard let merged else {
            return nil
        }

        persistLocally(merged)
        persistToCloud(merged)
        return merged
    }

    func saveState(dayStart: TimeInterval, usedCount: Int) {
        let incoming = SubscriptionQuotaState(dayStart: dayStart, usedCount: usedCount)
        let merged = mergedState(local: readLocalState(), cloud: readCloudState(), preferred: incoming) ?? incoming
        persistLocally(merged)
        persistToCloud(merged)
    }

    private func readLocalState() -> SubscriptionQuotaState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(SubscriptionQuotaState.self, from: data)
    }

    private func readCloudState() -> SubscriptionQuotaState? {
        guard let data = SubscriptionCloudMirrorStore.data(forKey: cloudAccount) else {
            return nil
        }
        return try? JSONDecoder().decode(SubscriptionQuotaState.self, from: data)
    }

    private func persistLocally(_ state: SubscriptionQuotaState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private func persistToCloud(_ state: SubscriptionQuotaState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        SubscriptionCloudMirrorStore.set(data, forKey: cloudAccount)
    }

    private func mergedState(
        local: SubscriptionQuotaState?,
        cloud: SubscriptionQuotaState?,
        preferred: SubscriptionQuotaState? = nil
    ) -> SubscriptionQuotaState? {
        let candidates = [preferred, local, cloud].compactMap { $0 }
        guard let newestDay = candidates.map(\.dayStart).max() else {
            return nil
        }
        let sameDayCandidates = candidates.filter { $0.dayStart == newestDay }
        let maxUsedCount = sameDayCandidates.map(\.usedCount).max() ?? 0
        return SubscriptionQuotaState(dayStart: newestDay, usedCount: maxUsedCount)
    }
}
