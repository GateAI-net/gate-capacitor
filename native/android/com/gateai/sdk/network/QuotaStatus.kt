package com.gateai.sdk.network

import com.gateai.sdk.util.Iso8601
import java.util.Date

/**
 * Remaining device quota, parsed from the `X-Quota-*` response headers.
 *
 * When a gate has device usage limits configured, every successful proxied response
 * carries `X-Quota-Requests-Remaining`, `X-Quota-Tokens-Remaining`,
 * `X-Quota-Requests-Reset`, `X-Quota-Tokens-Reset`, `X-Quota-Requests-Limit`, and
 * `X-Quota-Tokens-Limit` headers describing each metric's binding window. Read this
 * from [RawResponse.quotaStatus] to render limit UI (e.g., "N requests left" or a
 * usage meter) without parsing headers yourself.
 *
 * @property requestsRemaining Requests remaining in the binding request window, if reported
 * @property tokensRemaining Tokens remaining in the binding token window, if reported
 * @property requestsResetAt When the binding request window resets (for rolling windows,
 *   when the oldest counted day ages out), if reported
 * @property tokensResetAt When the binding token window resets (for rolling windows,
 *   when the oldest counted day ages out), if reported
 * @property requestsLimit Total request budget of the binding request window, if reported
 * @property tokensLimit Total token budget of the binding token window, if reported
 */
data class QuotaStatus(
    val requestsRemaining: Int?,
    val tokensRemaining: Int?,
    val requestsResetAt: Date?,
    val tokensResetAt: Date?,
    val requestsLimit: Int? = null,
    val tokensLimit: Int? = null
) {
    /**
     * Requests already used in the binding window (`requestsLimit - requestsRemaining`,
     * floored at 0). Exists so apps can render usage meters without doing the math.
     * Null unless both [requestsLimit] and [requestsRemaining] are present.
     */
    val requestsUsed: Int?
        get() = used(requestsLimit, requestsRemaining)

    /**
     * Tokens already used in the binding window (`tokensLimit - tokensRemaining`,
     * floored at 0). Exists so apps can render usage meters without doing the math.
     * Null unless both [tokensLimit] and [tokensRemaining] are present.
     */
    val tokensUsed: Int?
        get() = used(tokensLimit, tokensRemaining)

    /**
     * Fraction of the request budget consumed, in 0.0-1.0. Feed this straight into a
     * determinate progress bar to render a usage meter. Null unless [requestsUsed]
     * is available and [requestsLimit] > 0.
     */
    val requestsUsedFraction: Double?
        get() = usedFraction(requestsLimit, requestsUsed)

    /**
     * Fraction of the token budget consumed, in 0.0-1.0. Feed this straight into a
     * determinate progress bar to render a usage meter. Null unless [tokensUsed]
     * is available and [tokensLimit] > 0.
     */
    val tokensUsedFraction: Double?
        get() = usedFraction(tokensLimit, tokensUsed)

    private fun used(limit: Int?, remaining: Int?): Int? {
        if (limit == null || remaining == null) return null
        return (limit - remaining).coerceAtLeast(0)
    }

    private fun usedFraction(limit: Int?, used: Int?): Double? {
        if (limit == null || limit <= 0 || used == null) return null
        return (used.toDouble() / limit.toDouble()).coerceIn(0.0, 1.0)
    }

    companion object {
        private const val HEADER_REQUESTS_REMAINING = "x-quota-requests-remaining"
        private const val HEADER_TOKENS_REMAINING = "x-quota-tokens-remaining"
        private const val HEADER_REQUESTS_RESET = "x-quota-requests-reset"
        private const val HEADER_TOKENS_RESET = "x-quota-tokens-reset"
        private const val HEADER_REQUESTS_LIMIT = "x-quota-requests-limit"
        private const val HEADER_TOKENS_LIMIT = "x-quota-tokens-limit"

        /**
         * Parses quota status from response headers (case-insensitively).
         *
         * @param headers The response headers
         * @return A [QuotaStatus] if at least one of the six `X-Quota-*` headers is present,
         *   null otherwise
         */
        fun fromHeaders(headers: Map<String, String>): QuotaStatus? {
            val lowercased = HashMap<String, String>(headers.size)
            for ((key, value) in headers) {
                lowercased[key.lowercase()] = value
            }

            val requests = lowercased[HEADER_REQUESTS_REMAINING]
            val tokens = lowercased[HEADER_TOKENS_REMAINING]
            val requestsReset = lowercased[HEADER_REQUESTS_RESET]
            val tokensReset = lowercased[HEADER_TOKENS_RESET]
            val requestsLimit = lowercased[HEADER_REQUESTS_LIMIT]
            val tokensLimit = lowercased[HEADER_TOKENS_LIMIT]

            if (requests == null && tokens == null && requestsReset == null &&
                tokensReset == null && requestsLimit == null && tokensLimit == null
            ) {
                return null
            }

            return QuotaStatus(
                requestsRemaining = requests?.trim()?.toIntOrNull(),
                tokensRemaining = tokens?.trim()?.toIntOrNull(),
                requestsResetAt = Iso8601.parse(requestsReset),
                tokensResetAt = Iso8601.parse(tokensReset),
                requestsLimit = requestsLimit?.trim()?.toIntOrNull(),
                tokensLimit = tokensLimit?.trim()?.toIntOrNull()
            )
        }
    }
}

/**
 * Validation for the quota anchor day (day-of-month 1-31).
 */
internal object QuotaAnchorDay {
    val VALID_RANGE = 1..31

    /** Returns the day if it is a valid day-of-month (1-31), null otherwise. */
    fun sanitize(day: Int?): Int? = day?.takeIf { it in VALID_RANGE }
}
