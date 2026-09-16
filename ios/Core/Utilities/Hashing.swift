import Foundation
import CryptoKit

enum Hashing {
    static func sha256(_ data: Data) -> Data {
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }

    static func appAttestClientDataHash(nonce: Data, canonicalJWK: Data) -> Data {
        var combined = Data()
        combined.append(nonce)
        combined.append(sha256(canonicalJWK))
        return sha256(combined)
    }
}
