package com.gateai.sdk.auth

import com.gateai.sdk.core.AppInfo
import com.gateai.sdk.core.AttestationPayload
import com.gateai.sdk.core.DeviceKeyJwk
import com.gateai.sdk.core.GateAIConfiguration
import com.gateai.sdk.core.TokenRequest
import com.gateai.sdk.core.TokenResponse
import com.gateai.sdk.network.GateHttpClient
import kotlinx.serialization.Serializable

class AuthApiClient(private val httpClient: GateHttpClient) {

    suspend fun fetchChallenge(): ChallengeResponse {
        return httpClient.post(
            path = "attest/challenge",
            body = mapOf("purpose" to "token"),
            responseType = ChallengeResponse.serializer()
        )
    }

    suspend fun exchangeToken(
        configuration: GateAIConfiguration,
        deviceKeyJwk: DeviceKeyJwk,
        integrityToken: String?,
        dpopProof: String,
        developmentToken: String?,
        nonce: String? = null
    ): TokenResponse {
        val attestationPayload = integrityToken?.let {
            AttestationPayload(
                integrityToken = it,
                packageName = configuration.packageName,
                signingCertSha256 = configuration.signingCertSha256
            )
        }

        val request = TokenRequest(
            app = AppInfo(configuration.packageName),
            deviceKeyJwk = deviceKeyJwk,
            attestation = attestationPayload,
            devToken = developmentToken,
            // Server requires the challenge nonce alongside attestation
            nonce = if (attestationPayload != null) nonce else null,
            dpop = dpopProof
        )

        return httpClient.post(
            path = "token",
            body = request,
            responseType = TokenResponse.serializer(),
            dpop = dpopProof
        )
    }
}

@Serializable
data class ChallengeResponse(
    val nonce: String,
    val exp: Long
)


