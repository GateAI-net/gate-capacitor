import Foundation
import CryptoKit
@preconcurrency import Security

public struct DeviceKeyJWK: Codable, Sendable {
    public let kty: String
    public let crv: String
    public let x: String
    public let y: String

    enum CodingKeys: String, CodingKey {
        case kty
        case crv
        case x
        case y
    }

    public init(x: String, y: String) {
        self.kty = "EC"
        self.crv = "P-256"
        self.x = x
        self.y = y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kty = try container.decode(String.self, forKey: .kty)
        let crv = try container.decode(String.self, forKey: .crv)
        guard kty == "EC", crv == "P-256" else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unexpected JWK parameters."))
        }
        self.kty = kty
        self.crv = crv
        self.x = try container.decode(String.self, forKey: .x)
        self.y = try container.decode(String.self, forKey: .y)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kty, forKey: .kty)
        try container.encode(crv, forKey: .crv)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }

    func canonicalJSONString() -> String {
        return "{\"crv\":\"\(crv)\",\"kty\":\"\(kty)\",\"x\":\"\(x)\",\"y\":\"\(y)\"}"
    }

    func canonicalData() -> Data {
        Data(canonicalJSONString().utf8)
    }
}

public struct DeviceKeyMaterial: @unchecked Sendable { // SecKey is not Sendable; access stays within the auth actor.
    public let privateKey: SecKey
    public let jwk: DeviceKeyJWK
    public let thumbprint: String
}

final class DeviceKeyService {
    private let keyTag: Data

    init(bundleIdentifier: String) {
        let tagString = "com.gateai.device-key." + bundleIdentifier
        self.keyTag = Data(tagString.utf8)
    }

    func loadOrCreateKey() throws -> DeviceKeyMaterial {
        if let existingKey = try fetchExistingKey() {
            return try buildMaterial(from: existingKey)
        }

        let newKey = try createKey()
        return try buildMaterial(from: newKey)
    }

    private func fetchExistingKey() throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return (item as! SecKey)
        case errSecItemNotFound:
            return nil
        default:
            throw GateAIError.secureEnclaveUnavailable
        }
    }

    private func createKey() throws -> SecKey {
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [.privateKeyUsage],
            nil
        ) else {
            throw GateAIError.secureEnclaveUnavailable
        }

        let privateKeyAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrAccessControl as String: accessControl
        ]

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: privateKeyAttributes
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error {
                throw error.takeRetainedValue() as Error
            }
            throw GateAIError.secureEnclaveUnavailable
        }
        return privateKey
    }

    private func buildMaterial(from privateKey: SecKey) throws -> DeviceKeyMaterial {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw GateAIError.secureEnclaveUnavailable
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            if let error {
                throw error.takeRetainedValue() as Error
            }
            throw GateAIError.secureEnclaveUnavailable
        }

        guard publicKeyData.count == 65 && publicKeyData.first == 0x04 else {
            throw GateAIError.secureEnclaveUnavailable
        }

        let xData = publicKeyData[1..<33]
        let yData = publicKeyData[33..<65]

        let jwk = DeviceKeyJWK(x: Data(xData).base64URLEncodedString, y: Data(yData).base64URLEncodedString)
        let hash = SHA256.hash(data: jwk.canonicalData())
        let thumbprint = Data(hash).base64URLEncodedString

        return DeviceKeyMaterial(privateKey: privateKey, jwk: jwk, thumbprint: thumbprint)
    }
}
