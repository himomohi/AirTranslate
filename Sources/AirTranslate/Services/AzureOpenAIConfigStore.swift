import Foundation
import Security

enum AzureOpenAIConfigStore {
    private static let service = "AirTranslate.AzureOpenAI"
    private static let account = "AZURE_OPENAI_API_KEY"
    static let endpointDefaultsKey = "azureOpenAIEndpoint"
    private static let hasAPIKeyDefaultsKey = "azureOpenAIHasAPIKey"

    static func hasConfig() -> Bool {
        guard let endpoint = readEndpoint(), !endpoint.isEmpty else { return false }
        return UserDefaults.standard.bool(forKey: hasAPIKeyDefaultsKey)
    }

    static func readEndpoint() -> String? {
        UserDefaults.standard.string(forKey: endpointDefaultsKey)
    }

    static func readAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw OpenAIAPIKeyStoreError.keychainStatus(status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw OpenAIAPIKeyStoreError.invalidStoredKey
        }
        if !key.isEmpty, !UserDefaults.standard.bool(forKey: hasAPIKeyDefaultsKey) {
            UserDefaults.standard.set(true, forKey: hasAPIKeyDefaultsKey)
        }
        return key
    }

    static func saveConfig(endpoint: String, apiKey: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIAPIKeyStoreError.emptyKey
        }
        guard let normalizedEndpoint = AzureOpenAIEndpoint.normalize(endpoint) else {
            throw AzureOpenAIConfigStoreError.invalidEndpoint
        }
        guard let data = trimmedKey.data(using: .utf8) else {
            throw OpenAIAPIKeyStoreError.invalidStoredKey
        }

        SecItemDelete(baseQuery() as CFDictionary)

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw OpenAIAPIKeyStoreError.keychainStatus(status)
        }
        UserDefaults.standard.set(true, forKey: hasAPIKeyDefaultsKey)
        UserDefaults.standard.set(normalizedEndpoint, forKey: endpointDefaultsKey)
    }

    static func deleteConfig() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAIAPIKeyStoreError.keychainStatus(status)
        }
        UserDefaults.standard.set(false, forKey: hasAPIKeyDefaultsKey)
        UserDefaults.standard.removeObject(forKey: endpointDefaultsKey)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum AzureOpenAIEndpoint {
    static func normalize(_ input: String) -> String? {
        parse(input)?.normalized
    }

    static func host(from endpoint: String) -> String? {
        parse(endpoint)?.host
    }

    private static func parse(_ input: String) -> (normalized: String, host: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let host = url.host, !host.isEmpty else { return nil }

        var components = URLComponents()
        let scheme = (url.scheme ?? "https").lowercased()
        components.scheme = scheme == "http" ? "http" : "https"
        components.host = host
        if let port = url.port { components.port = port }
        guard let normalized = components.string else { return nil }
        return (normalized, host)
    }
}

enum AzureOpenAIConfigStoreError: LocalizedError {
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            AppText.azureOpenAIEndpointInvalid
        }
    }
}
