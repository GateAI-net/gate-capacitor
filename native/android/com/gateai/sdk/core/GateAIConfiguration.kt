package com.gateai.sdk.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

data class GateAIConfiguration(
    val baseUrl: String,
    val packageName: String,
    val signingCertSha256: String,
    val developmentToken: String? = null,
    val cloudProjectNumber: Long? = null,
    val logLevel: LogLevel = LogLevel.INFO,
    /**
     * When true, the SDK sends the device's ANDROID_ID as the X-Device-Identifier header.
     * ANDROID_ID is a persistent per-app, per-device identifier; enabling this creates a
     * data-collection disclosure obligation (Play Data safety, privacy policy, GDPR/COPPA
     * depending on your app). Defaults to false — opt in only if you need per-device
     * analytics and have disclosed it.
     */
    val deviceIdentifierEnabled: Boolean = false
) {
    init {
        require(baseUrl.startsWith("https://")) { "baseUrl must start with https://" }
        require(packageName.isNotBlank()) { "packageName cannot be blank" }
        require(signingCertSha256.matches(Regex("^[0-9A-Fa-f:]{59,}$"))) {
            "signingCertSha256 must be a hex SHA-256 fingerprint (colon-delimited or raw hex)"
        }
    }

    enum class LogLevel { OFF, ERROR, WARN, INFO, DEBUG }
}

@Serializable
data class DeviceKeyJwk(
    val kty: String = "EC",
    val crv: String = "P-256",
    val x: String,
    val y: String
) {
    init {
        require(kty == "EC") { "Only EC keys are supported" }
        require(crv == "P-256") { "Only P-256 curve is supported" }
    }
}

@Serializable
data class TokenRequest(
    val platform: String = "android",
    val app: AppInfo,
    @SerialName("device_key_jwk") val deviceKeyJwk: DeviceKeyJwk,
    val attestation: AttestationPayload? = null,
    @SerialName("dev_token") val devToken: String? = null,
    val nonce: String? = null,
    val dpop: String
)

@Serializable
data class AppInfo(
    @SerialName("package_name") val packageName: String
)

@Serializable
data class AttestationPayload(
    val type: String = "play_integrity",
    @SerialName("integrity_token") val integrityToken: String,
    @SerialName("package_name") val packageName: String,
    @SerialName("signing_cert_sha256") val signingCertSha256: String
)

@Serializable
data class TokenResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("expires_in") val expiresInSeconds: Long,
    val mode: String? = null
)


