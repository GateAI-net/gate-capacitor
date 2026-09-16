import Foundation

struct AuthorizationContext: Sendable {
    let accessToken: String
    let dpop: String
}

actor GateAIAuthSession {
    private let configuration: GateAIConfiguration
    private let apiClient: AuthAPIClient
    private let deviceKeyService: DeviceKeyService
    private let appAttestService: GateAIAppAttestProvider
    private let developmentToken: String?
    private let logger: GateAILoggerProtocol
    private var deviceKeyMaterial: DeviceKeyMaterial?
    private var dpopBuilder: DPoPTokenBuilder?
    private var cachedToken: String?
    private var tokenExpiry: Date?
    private var mintTask: Task<TokenResponse, Error>?

    init(
        configuration: GateAIConfiguration,
        apiClient: AuthAPIClient,
        deviceKeyService: DeviceKeyService,
        appAttestService: GateAIAppAttestProvider,
        developmentToken: String?,
        logger: GateAILoggerProtocol = GateAILogger.shared
    ) {
        self.configuration = configuration
        self.apiClient = apiClient
        self.deviceKeyService = deviceKeyService
        self.appAttestService = appAttestService
        self.developmentToken = developmentToken
        self.logger = logger
    }

    func authorizationHeaders(for url: URL, method: HTTPMethod, nonce: String? = nil) async throws -> AuthorizationContext {
        let token = try await ensureValidToken()
        guard let builder = dpopBuilder else {
            throw GateAIError.secureEnclaveUnavailable
        }
        let proof = try builder.proof(httpMethod: method, url: url, nonce: nonce)
        return AuthorizationContext(accessToken: token, dpop: proof)
    }

    func accessToken() async throws -> String {
        return try await ensureValidToken()
    }

    func reset() {
        mintTask?.cancel()
        mintTask = nil
        cachedToken = nil
        tokenExpiry = nil
    }

    private func ensureValidToken() async throws -> String {
        if let token = cachedToken, let expiry = tokenExpiry, expiry.timeIntervalSinceNow > 60 {
            logger.debug("Using cached access token (expires in \(Int(expiry.timeIntervalSinceNow))s)")
            return token
        }

        logger.debug("Access token missing or expired, minting new token")

        if let existingTask = mintTask {
            logger.debug("Waiting for existing token mint task")
            let response = try await existingTask.value
            mintTask = nil
            updateTokenCache(with: response)
            return response.accessToken
        }

        let task = Task<TokenResponse, Error> {
            try await self.mintAccessToken()
        }
        mintTask = task

        do {
            let response = try await task.value
            updateTokenCache(with: response)
            mintTask = nil
            logger.info("Successfully minted new access token")
            return response.accessToken
        } catch {
            mintTask = nil
            logger.error("Failed to mint access token: \(error)")
            throw error
        }
    }

    private func updateTokenCache(with response: TokenResponse) {
        cachedToken = response.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(response.expiresIn))
    }

    private func mintAccessToken() async throws -> TokenResponse {
        let material = try ensureDeviceKeyMaterial()
        guard let builder = dpopBuilder else {
            logger.error("Secure Enclave unavailable for DPoP token generation")
            throw GateAIError.secureEnclaveUnavailable
        }

        if shouldUseDevelopmentFlow {
            logger.info("Using development token flow (simulator)")
            return try await mintUsingDevelopmentToken(material: material, builder: builder)
        }

        logger.info("Using App Attest flow (device)")
        return try await mintUsingAppAttest(material: material, builder: builder)
    }

    private var shouldUseDevelopmentFlow: Bool {
        guard Platform.isSimulator, let token = developmentToken, !token.isEmpty else { return false }
        return true
    }

    private func mintUsingAppAttest(material: DeviceKeyMaterial, builder: DPoPTokenBuilder) async throws -> TokenResponse {
        let canonicalJWK = material.jwk.canonicalData()
        let canonicalJWKString = material.jwk.canonicalJSONString()

        logger.debug("Canonical JWK: \(canonicalJWKString)")
        logger.debug("Device JWK thumbprint: \(material.thumbprint)")

        // Try up to 2 times: once with existing key, once after regenerating key + challenge if invalid
        for attempt in 1...2 {
            let challenge = try await apiClient.fetchChallenge()
            guard let nonceData = challenge.nonce.base64URLDecodedData
                    ?? Data(base64Encoded: challenge.nonce)
                    ?? challenge.nonce.data(using: .utf8) else {
                throw GateAIError.configuration("Failed to decode server nonce.")
            }

            logger.debug("Attempt \(attempt) nonce (base64url): \(challenge.nonce)")
            logger.debug("Attempt \(attempt) nonce (hex): \(nonceData.map { String(format: "%02x", $0) }.joined())")

            let clientDataHash = Hashing.appAttestClientDataHash(nonce: nonceData, canonicalJWK: canonicalJWK)
            logger.debug("Attempt \(attempt) client data hash (hex): \(clientDataHash.map { String(format: "%02x", $0) }.joined())")
            logger.debug("Attempt \(attempt) client data hash (base64): \(clientDataHash.base64EncodedString())")

            let keyID: String
            do {
                keyID = try await appAttestService.ensureKeyID()
            } catch let error as GateAIError {
                throw error
            } catch {
                throw GateAIError.attestationFailed("Failed to ensure attestation key: \(error.localizedDescription)")
            }

            // A key that has never completed Apple attestation cannot assert —
            // attest and register it first. (Probing generateAssertion and
            // relying on devicecheck error 0 is unreliable: some OS versions
            // return error 3 for unattested keys, which reads as "corrupt key"
            // and dead-ends the retry loop.)
            if !appAttestService.hasAttestedKey() {
                logger.info("Key not yet attested, performing attestation for keyID: \(keyID)")
                do {
                    try await performAttestationRegistration(
                        keyID: keyID,
                        clientDataHash: clientDataHash,
                        material: material,
                        builder: builder,
                        challenge: challenge
                    )

                    logger.debug("Generating assertion after registration for keyID: \(keyID)")
                    let newAssertionData = try await appAttestService.generateAssertion(keyID: keyID, clientDataHash: clientDataHash)

                    let attestation = TokenRequestBody.Attestation(
                        type: "app_attest",
                        keyId: keyID,
                        teamId: configuration.teamIdentifier,
                        assertion: newAssertionData.base64EncodedString()
                    )

                    return try await exchangeToken(material: material, builder: builder, attestation: attestation, devToken: nil, nonce: challenge.nonce)
                } catch {
                    logger.error("Failed to register attestation: \(error.localizedDescription)")
                    if let gateError = error as? GateAIError {
                        if case let .server(_, serverError, _) = gateError, let serverError {
                            let description = serverError.errorDescription ?? serverError.error
                            throw GateAIError.attestationFailed(description)
                        }
                        throw gateError
                    }
                    throw GateAIError.attestationFailed("Failed to register attestation key with server: \(error.localizedDescription)")
                }
            }

            let assertionData: Data
            do {
                logger.debug("Generating attestation/assertion for keyID: \(keyID) (attempt \(attempt))")
                // Try to generate assertion first (for existing attested keys)
                assertionData = try await appAttestService.generateAssertion(keyID: keyID, clientDataHash: clientDataHash)
                logger.debug("Successfully generated assertion data (\(assertionData.count) bytes)")
            } catch let error as GateAIError {
                logger.error("GateAI error during assertion generation: \(error)")
                throw error
            } catch {
                let nsError = error as NSError
                // Error code 0 means key not attested yet, error codes 2/3 mean invalid key
                if nsError.domain == "com.apple.devicecheck.error" {
                    if nsError.code == 0 {
                        // Key needs attestation - this is a new key, call registration endpoint
                        logger.info("Key not attested yet, performing attestation for keyID: \(keyID)")
                        do {
                            try await performAttestationRegistration(
                                keyID: keyID,
                                clientDataHash: clientDataHash,
                                material: material,
                                builder: builder,
                                challenge: challenge
                            )

                            // Now generate assertion with the newly registered key
                            logger.debug("Generating assertion after registration for keyID: \(keyID)")
                            let newAssertionData = try await appAttestService.generateAssertion(keyID: keyID, clientDataHash: clientDataHash)
                            logger.debug("Successfully generated assertion data (\(newAssertionData.count) bytes)")

                            let attestation = TokenRequestBody.Attestation(
                                type: "app_attest",
                                keyId: keyID,
                                teamId: configuration.teamIdentifier,
                                assertion: newAssertionData.base64EncodedString()
                            )

                            return try await exchangeToken(material: material, builder: builder, attestation: attestation, devToken: nil, nonce: challenge.nonce)
                        } catch {
                            logger.error("Failed to register attestation: \(error.localizedDescription)")
                            if let gateError = error as? GateAIError {
                                if case let .server(_, serverError, _) = gateError, let serverError {
                                    let description = serverError.errorDescription ?? serverError.error
                                    throw GateAIError.attestationFailed(description)
                                }
                                throw gateError
                            }
                            throw GateAIError.attestationFailed("Failed to register attestation key with server: \(error.localizedDescription)")
                        }
                    } else if (nsError.code == 2 || nsError.code == 3) && attempt == 1 {
                        // Invalid key or key identifier - retry with new key
                        logger.warning("Invalid key detected (error \(nsError.code)) on attempt \(attempt), will retry with new key")
                        continue
                    }
                }
                logger.error("System error during assertion generation: \(error.localizedDescription) - \(error)")
                throw GateAIError.attestationFailed("Failed to generate device attestation: \(error.localizedDescription)")
            }

            let attestation = TokenRequestBody.Attestation(
                type: "app_attest",
                keyId: keyID,
                teamId: configuration.teamIdentifier,
                assertion: assertionData.base64EncodedString()
            )

            // Try to exchange token - if server says key is not registered, perform registration
            do {
                return try await exchangeToken(material: material, builder: builder, attestation: attestation, devToken: nil, nonce: challenge.nonce)
            } catch let error as GateAIError {
                // Check if this is a server-side attestation registration error
                if case let .server(statusCode, serverError, _) = error,
                   statusCode == 401,
                   serverError?.error == "attestation_failed",
                   serverError?.errorDescription?.contains("registration required") == true {

                    logger.warning("Server reports attestation key not registered for keyID: \(keyID)")

                    // The key was already attested locally (since generateAssertion succeeded),
                    // but the server doesn't know about it. We can't re-attest an already-attested key,
                    // so we need to clear it and generate a new one on the next iteration.
                    if attempt == 1 {
                        logger.info("Clearing locally attested key, will fetch new challenge and retry")
                        try? appAttestService.clearStoredKey()
                        continue
                    }
                }
                throw error
            }
        }

        // Should never reach here, but just in case
        throw GateAIError.attestationFailed("Failed to complete device attestation after multiple attempts.")
    }

    private func performAttestationRegistration(
        keyID: String,
        clientDataHash: Data,
        material: DeviceKeyMaterial,
        builder: DPoPTokenBuilder,
        challenge: ChallengeResponse
    ) async throws {
        let attestationData = try await appAttestService.attestKey(keyID: keyID, clientDataHash: clientDataHash)
        logger.debug("Successfully attested key (\(attestationData.count) bytes)")

        // Register the attested key with the server
        let registrationURL = configuration.baseURL.appendingPathComponent("attest/register")
        let registrationProof = try builder.proof(httpMethod: .post, url: registrationURL, nonce: nil)

        let registrationBody = RegistrationRequestBody(
            app: RegistrationRequestBody.AppDescriptor(bundleId: configuration.bundleIdentifier),
            deviceKeyJwk: material.jwk,
            attestation: RegistrationRequestBody.AppAttestRegistration(
                type: "app_attest",
                keyId: keyID,
                teamId: configuration.teamIdentifier,
                attestation: attestationData.base64EncodedString()
            ),
            nonce: challenge.nonce,
            dpop: registrationProof
        )

        let _ = try await apiClient.registerAttestation(body: registrationBody, dpop: registrationProof)
        logger.info("Successfully registered App Attest key with server")

        // Mark key as attested locally
        try appAttestService.markKeyAsAttested(keyID)
    }

    private func mintUsingDevelopmentToken(material: DeviceKeyMaterial, builder: DPoPTokenBuilder) async throws -> TokenResponse {
        guard Platform.isSimulator else {
            logger.error("Development token flow attempted on device - not allowed")
            throw GateAIError.configuration("Development token flow is restricted to the simulator.")
        }
        guard let token = developmentToken, !token.isEmpty else {
            logger.error("Development token is missing or empty")
            throw GateAIError.configuration("Development token is missing or empty.")
        }

        logger.debug("Exchanging development token for access token")
        return try await exchangeToken(material: material, builder: builder, attestation: nil, devToken: token, nonce: nil)
    }

    private func exchangeToken(
        material: DeviceKeyMaterial,
        builder: DPoPTokenBuilder,
        attestation: TokenRequestBody.Attestation?,
        devToken: String?,
        nonce challengeNonce: String?
    ) async throws -> TokenResponse {
        let tokenURL = configuration.baseURL.appendingPathComponent("token")
        let appDescriptor = TokenRequestBody.AppDescriptor(bundleId: configuration.bundleIdentifier)

        func sendTokenRequest(with dpopNonce: String?) async throws -> TokenResponse {
            let proof = try builder.proof(httpMethod: .post, url: tokenURL, nonce: dpopNonce)
            let body = TokenRequestBody(
                app: appDescriptor,
                deviceKeyJwk: material.jwk,
                attestation: attestation,
                devToken: devToken,
                nonce: challengeNonce,
                dpop: proof
            )
            return try await apiClient.exchangeToken(body: body, dpop: proof)
        }

        do {
            return try await sendTokenRequest(with: nil)
        } catch let error as GateAIError {
            guard case let .server(status, _, headers) = error,
                  status == 401,
                  let nonce = headers?[caseInsensitive: "DPoP-Nonce"] else {
                throw error
            }

            // Server requested a proof with the supplied nonce—reissue DPoP and retry once.
            return try await sendTokenRequest(with: nonce)
        }
    }

    private func ensureDeviceKeyMaterial() throws -> DeviceKeyMaterial {
        if let material = deviceKeyMaterial {
            logger.debug("Reusing existing device key material")
            return material
        }

        logger.debug("Loading or creating device key material")
        let material = try deviceKeyService.loadOrCreateKey()
        deviceKeyMaterial = material
        dpopBuilder = DPoPTokenBuilder(material: material)
        logger.info("Device key material ready (thumbprint: \(material.thumbprint))")
        return material
    }
}
