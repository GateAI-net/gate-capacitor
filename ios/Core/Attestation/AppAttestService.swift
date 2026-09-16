import Foundation
@preconcurrency import Security
#if canImport(DeviceCheck)
@preconcurrency import DeviceCheck
#endif

struct AppAttestKeyData: Codable {
    let keyID: String
    let attested: Bool
}

struct AppAttestKeyStore: Sendable {
    private let account: String

    init(bundleIdentifier: String) {
        self.account = "com.gateai.appattest." + bundleIdentifier
    }

    func loadAttestedKey() throws -> AppAttestKeyData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }

            // Try new format first (JSON)
            if let keyData = try? JSONDecoder().decode(AppAttestKeyData.self, from: data), keyData.attested {
                return keyData
            }

            // Fall back to old format (plain string) - treat as unattested
            return nil

        case errSecItemNotFound:
            return nil
        default:
            throw GateAIError.attestationFailed("Failed to access secure storage")
        }
    }

    func storeAttestedKey(keyID: String) throws {
        let keyData = AppAttestKeyData(keyID: keyID, attested: true)
        let data = try JSONEncoder().encode(keyData)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(baseQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw GateAIError.attestationFailed("Failed to update secure storage")
            }
        } else if status != errSecSuccess {
            throw GateAIError.attestationFailed("Failed to write to secure storage")
        }
    }

    func deleteKeyID() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GateAIError.attestationFailed("Failed to delete from secure storage")
        }
    }
}

#if canImport(DeviceCheck)
@available(iOS 14.0, *)
final class AppAttestService: @unchecked Sendable { // DeviceCheck APIs are main-thread bound; we guard usage manually.
    private let service: DCAppAttestService
    private let keyStore: AppAttestKeyStore

    init(bundleIdentifier: String, service: DCAppAttestService = .shared) {
        self.service = service
        self.keyStore = AppAttestKeyStore(bundleIdentifier: bundleIdentifier)
    }
}

@available(iOS 14.0, *)
extension AppAttestService: GateAIAppAttestProvider {
    func ensureKeyID() async throws -> String {
        let isSupported = service.isSupported
        GateAILogger.shared.debug("DCAppAttestService.isSupported: \(isSupported)")

        #if targetEnvironment(simulator)
        GateAILogger.shared.debug("Running on simulator - App Attest not available")
        #else
        GateAILogger.shared.debug("Running on device")
        #endif

        guard isSupported else {
            GateAILogger.shared.error("App Attest is not supported on this device. Reasons could be: unsupported hardware, region restrictions, or MDM policies.")
            throw GateAIError.attestationUnavailable
        }

        if let stored = try keyStore.loadAttestedKey() {
            GateAILogger.shared.debug("Using existing attested App Attest key ID: \(stored.keyID)")
            return stored.keyID
        }

        GateAILogger.shared.debug("Generating new App Attest key")
        let newKeyID = try await generateKey()
        GateAILogger.shared.info("Generated new App Attest key ID: \(newKeyID)")
        return newKeyID
    }

    func markKeyAsAttested(_ keyID: String) throws {
        try keyStore.storeAttestedKey(keyID: keyID)
        GateAILogger.shared.info("Marked key as attested: \(keyID)")
    }

    func hasAttestedKey() -> Bool {
        (try? keyStore.loadAttestedKey()) != nil
    }

    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data {
        GateAILogger.shared.debug("Attesting key with Apple: \(keyID)")
        return try await withCheckedThrowingContinuation { continuation in
            service.attestKey(keyID, clientDataHash: clientDataHash) { attestation, error in
                if let error {
                    GateAILogger.shared.error("DCAppAttestService.attestKey failed: \(error.localizedDescription) - \((error as NSError).domain):\((error as NSError).code)")
                    continuation.resume(throwing: error)
                } else if let attestation {
                    GateAILogger.shared.debug("Successfully attested key, attestation size: \(attestation.count) bytes")
                    continuation.resume(returning: attestation)
                } else {
                    GateAILogger.shared.error("DCAppAttestService.attestKey returned neither attestation nor error")
                    continuation.resume(throwing: GateAIError.attestationUnavailable)
                }
            }
        }
    }

    func generateAssertion(keyID: String, clientDataHash: Data) async throws -> Data {
        GateAILogger.shared.debug("Calling DCAppAttestService.generateAssertion for keyID: \(keyID), clientDataHash: \(clientDataHash.count) bytes")
        do {
            return try await withCheckedThrowingContinuation { continuation in
                service.generateAssertion(keyID, clientDataHash: clientDataHash) { assertion, error in
                    if let error {
                        GateAILogger.shared.error("DCAppAttestService.generateAssertion failed: \(error.localizedDescription) - \((error as NSError).domain):\((error as NSError).code)")
                        continuation.resume(throwing: error)
                    } else if let assertion {
                        GateAILogger.shared.debug("DCAppAttestService.generateAssertion succeeded, assertion size: \(assertion.count) bytes")
                        continuation.resume(returning: assertion)
                    } else {
                        GateAILogger.shared.error("DCAppAttestService.generateAssertion returned neither assertion nor error")
                        continuation.resume(throwing: GateAIError.attestationUnavailable)
                    }
                }
            }
        } catch {
            // Check if this is an invalid key error (error codes 2 or 3)
            let nsError = error as NSError
            if nsError.domain == "com.apple.devicecheck.error" && (nsError.code == 2 || nsError.code == 3) {
                GateAILogger.shared.warning("Invalid key detected (error \(nsError.code)), deleting and regenerating...")
                try keyStore.deleteKeyID()
                GateAILogger.shared.info("Deleted invalid key, caller should regenerate")
            }
            throw error
        }
    }

    func clearStoredKey() throws {
        GateAILogger.shared.info("Clearing stored App Attest key")
        try keyStore.deleteKeyID()
    }

    private func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            service.generateKey { keyID, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let keyID {
                    continuation.resume(returning: keyID)
                } else {
                    continuation.resume(throwing: GateAIError.attestationUnavailable)
                }
            }
        }
    }
}
#endif
