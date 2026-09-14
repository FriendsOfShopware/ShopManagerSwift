import Foundation
import CryptoKit
import Security

/// AES-GCM string encryption backed by a Keychain-stored symmetric key; ciphertexts are
/// Base64(nonce || ciphertext || tag) — the CryptoKit `combined` layout. The Apple analogue of
/// the Android `Crypto` object (AndroidKeyStore-backed AES-GCM). Refresh tokens and recovery
/// passwords are encrypted; the encryption key is stored only on this device.
enum Crypto {
    private static let keyTag = "de.shyim.shopware.credentials-key"

    enum CryptoError: Error { case keyUnavailable, decodeFailed }

    /// Loads the symmetric key from the Keychain, generating and storing it on first use.
    private static func key() throws -> SymmetricKey {
        if let existing = try loadKey() { return existing }
        let newKey = SymmetricKey(size: .bits256)
        try storeKey(newKey)
        return newKey
    }

    static func encrypt(_ plain: String) throws -> String {
        let sealed = try AES.GCM.seal(Data(plain.utf8), using: key())
        guard let combined = sealed.combined else { throw CryptoError.keyUnavailable }
        return combined.base64EncodedString()
    }

    static func decrypt(_ enc: String) throws -> String {
        guard let data = Data(base64Encoded: enc) else { throw CryptoError.decodeFailed }
        let box = try AES.GCM.SealedBox(combined: data)
        let opened = try AES.GCM.open(box, using: key())
        return String(decoding: opened, as: UTF8.self)
    }

    // MARK: - Keychain key storage

    private static func loadKey() throws -> SymmetricKey? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw CryptoError.keyUnavailable
        }
    }

    private static func storeKey(_ key: SymmetricKey) throws {
        let raw = key.withUnsafeBytes { Data($0) }
        var query = baseQuery()
        query[kSecValueData as String] = raw
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw CryptoError.keyUnavailable
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyTag,
            kSecAttrAccount as String: "aes-gcm",
        ]
    }
}
