package com.gateai.sdk.network

import com.gateai.sdk.util.Iso8601
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.Date

/**
 * Structured details of a rate-limit rejection, parsed from a 429 `rate_limited` response body.
 *
 * The Gate/AI proxy rejects over-limit requests with a JSON body identifying which
 * limit fired. Device-window rejections (daily / monthly / rolling 30-day / billing-cycle
 * caps) additionally carry the window, the limit, usage so far, and when capacity returns.
 * Read this from [GateApiException.rateLimitInfo] to render limit UI (e.g., a paywall or
 * "resets in N days") without parsing the body yourself.
 *
 * @property code The rejection code (e.g., `device_monthly_requests_exceeded`)
 * @property message Human-readable description of the rejection
 * @property window The device usage window that fired, if this was a device-window rejection
 * @property limit The configured limit for the window, if reported
 * @property used Usage counted in the window (excluding the rejected request), if reported
 * @property resetsAt When capacity returns (for rolling windows, when the oldest counted
 *   day ages out), if reported
 */
data class RateLimitInfo(
    val code: String,
    val message: String,
    val window: Window? = null,
    val limit: Int? = null,
    val used: Int? = null,
    val resetsAt: Date? = null
) {
    /**
     * The device usage window that triggered a rate-limit rejection.
     *
     * Decodes unknown-safely: window values this SDK version doesn't know about are
     * preserved as [Unknown] with the raw string intact.
     */
    sealed class Window {
        /** UTC calendar day. */
        object Daily : Window()

        /** UTC calendar month (since the 1st). */
        object Monthly : Window()

        /** Trailing 30 days; capacity returns gradually as old days age out. */
        object Rolling30d : Window()

        /** The user's billing cycle, anchored to `quotaAnchorDay`. */
        object Cycle : Window()

        /** A window value not known to this SDK version; [value] preserves the raw string. */
        data class Unknown(val value: String) : Window()

        /** The raw wire value (e.g., "daily", "rolling_30d"). */
        val rawValue: String
            get() = when (this) {
                Daily -> "daily"
                Monthly -> "monthly"
                Rolling30d -> "rolling_30d"
                Cycle -> "cycle"
                is Unknown -> value
            }

        companion object {
            /** Maps a wire value to a [Window]; unknown values become [Unknown]. */
            fun fromRawValue(value: String): Window = when (value) {
                "daily" -> Daily
                "monthly" -> Monthly
                "rolling_30d" -> Rolling30d
                "cycle" -> Cycle
                else -> Unknown(value)
            }
        }
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /**
         * Parses a 429 `rate_limited` JSON body.
         *
         * @param body The response body of a 429 response
         * @return A [RateLimitInfo] if the body is a parseable rate-limited rejection,
         *   null otherwise (e.g., a provider's own 429 passed through the proxy)
         */
        fun parse(body: String?): RateLimitInfo? {
            if (body.isNullOrBlank()) return null
            val decoded = try {
                json.decodeFromString(RateLimitBody.serializer(), body)
            } catch (_: Exception) {
                return null
            }

            if (decoded.error != "rate_limited") return null
            val code = decoded.code ?: return null
            val message = decoded.message ?: return null

            return RateLimitInfo(
                code = code,
                message = message,
                window = decoded.window?.let { Window.fromRawValue(it) },
                limit = decoded.limit?.toIntOrNull(),
                used = decoded.used?.toIntOrNull(),
                resetsAt = Iso8601.parse(decoded.resetsAt)
            )
        }

        private fun Long.toIntOrNull(): Int? =
            if (this in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) toInt() else null
    }

    @Serializable
    private data class RateLimitBody(
        val error: String? = null,
        val code: String? = null,
        val message: String? = null,
        val window: String? = null,
        val limit: Long? = null,
        val used: Long? = null,
        @SerialName("resets_at") val resetsAt: String? = null
    )
}
