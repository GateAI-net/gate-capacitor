import Foundation
@preconcurrency import Security

struct DPoPTokenBuilder {
    private let jwk: DeviceKeyJWK
    private let privateKey: SecKey

    init(material: DeviceKeyMaterial) {
        self.jwk = material.jwk
        self.privateKey = material.privateKey
    }

    func proof(
        httpMethod: HTTPMethod,
        url: URL,
        nonce: String? = nil,
        issuedAt: Date = Date(),
        jti: UUID = UUID()
    ) throws -> String {
        let headerJSON = try encodeHeader()
        let payloadJSON = try encodePayload(
            method: httpMethod,
            url: url,
            nonce: nonce,
            issuedAt: issuedAt,
            jti: jti
        )

        let signingInput = [headerJSON.base64URLEncodedString, payloadJSON.base64URLEncodedString].joined(separator: ".")
        let signature = try sign(message: Data(signingInput.utf8))
        let signatureComponent = signature.base64URLEncodedString
        return [signingInput, signatureComponent].joined(separator: ".")
    }

    private func encodeHeader() throws -> Data {
        let header: [String: Any] = [
            "typ": "dpop+jwt",
            "alg": "ES256",
            "jwk": [
                "kty": jwk.kty,
                "crv": jwk.crv,
                "x": jwk.x,
                "y": jwk.y
            ]
        ]
        return try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
    }

    private func encodePayload(
        method: HTTPMethod,
        url: URL,
        nonce: String?,
        issuedAt: Date,
        jti: UUID
    ) throws -> Data {
        var payload: [String: Any] = [
            "htu": url.absoluteString,
            "htm": method.rawValue,
            "iat": Int(issuedAt.timeIntervalSince1970),
            "jti": jti.uuidString
        ]
        if let nonce {
            payload["nonce"] = nonce
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private func sign(message: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let derSignature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            message as CFData,
            &error
        ) as Data? else {
            if let error {
                throw error.takeRetainedValue() as Error
            }
            throw GateAIError.secureEnclaveUnavailable
        }
        return try DER.ecdsaSignatureToRaw(derSignature, coordinateOctetLength: 32)
    }
}
