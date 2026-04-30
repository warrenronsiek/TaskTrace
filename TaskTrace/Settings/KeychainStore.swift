//
//  KeychainStore.swift
//  TaskTrace
//
//  Created by Codex on 3/12/26.
//

import Foundation
import Security

protocol KeychainStoring {
    func loadValue(for key: String) throws -> String?
    func saveValue(_ value: String, for key: String) throws
}

struct KeychainStore: KeychainStoring {
    func loadValue(for key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }

        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidData
        }

        return value
    }

    func saveValue(_ value: String, for key: String) throws {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedValue.isEmpty {
            let status = SecItemDelete(baseQuery(for: key) as CFDictionary)

            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainStoreError.unexpectedStatus(status)
            }

            return
        }

        let encodedValue = Data(normalizedValue.utf8)
        let status = SecItemUpdate(
            baseQuery(for: key) as CFDictionary,
            [kSecValueData as String: encodedValue] as CFDictionary
        )

        if status == errSecSuccess {
            return
        }

        if status != errSecItemNotFound {
            throw KeychainStoreError.unexpectedStatus(status)
        }

        let addStatus = SecItemAdd(
            baseQuery(for: key).merging([kSecValueData as String: encodedValue], uniquingKeysWith: { current, _ in current }) as CFDictionary,
            nil
        )

        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Vars.keychainService,
            kSecAttrAccount as String: key
        ]
    }
}

enum KeychainStoreError: Error {
    case invalidData
    case unexpectedStatus(OSStatus)
}
