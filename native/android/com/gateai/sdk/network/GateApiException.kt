package com.gateai.sdk.network

class GateApiException(
    val statusCode: Int,
    val headers: Map<String, String>,
    val body: String?
) : Exception("HTTP $statusCode") {

    /**
     * Structured rate-limit details when this is a 429 `rate_limited` rejection
     * from the Gate/AI proxy, null otherwise (including provider 429s passed through).
     *
     * ## Example
     *
     * ```kotlin
     * catch (e: GateApiException) {
     *     e.rateLimitInfo?.let { info ->
     *         // e.g., show a paywall or "resets at ${info.resetsAt}"
     *     }
     * }
     * ```
     */
    val rateLimitInfo: RateLimitInfo? by lazy {
        if (statusCode == 429) RateLimitInfo.parse(body) else null
    }
}
