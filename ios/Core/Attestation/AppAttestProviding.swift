import Foundation

public protocol GateAIAppAttestProvider: Sendable {
    func ensureKeyID() async throws -> String
    /// Whether the current stored key has completed Apple attestation.
    /// New keys must be attested (and registered) before they can assert.
    func hasAttestedKey() -> Bool
    func markKeyAsAttested(_ keyID: String) throws
    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(keyID: String, clientDataHash: Data) async throws -> Data
    func clearStoredKey() throws
}

struct UnsupportedAppAttestService: GateAIAppAttestProvider {
    func ensureKeyID() async throws -> String {
        throw GateAIError.attestationUnavailable
    }

    func hasAttestedKey() -> Bool {
        false
    }

    func markKeyAsAttested(_ keyID: String) throws {
        throw GateAIError.attestationUnavailable
    }

    func attestKey(keyID: String, clientDataHash: Data) async throws -> Data {
        throw GateAIError.attestationUnavailable
    }

    func generateAssertion(keyID: String, clientDataHash: Data) async throws -> Data {
        throw GateAIError.attestationUnavailable
    }

    func clearStoredKey() throws {
        // No-op for unsupported service
    }
}
