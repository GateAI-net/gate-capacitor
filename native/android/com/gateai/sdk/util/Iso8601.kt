package com.gateai.sdk.util

import java.text.ParseException
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Minimal ISO 8601 timestamp parser.
 *
 * Tolerates fractional seconds of any precision (the server sends JS
 * `Date.toISOString()` values like `2026-09-01T00:00:00.000Z`), plain `Z`
 * timestamps, and numeric UTC offsets. Uses [SimpleDateFormat] because the
 * SDK's minSdk (24) predates `java.time`.
 */
internal object Iso8601 {

    private val FRACTION = Regex("""\.(\d+)""")

    private val PATTERNS = listOf(
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXX"
    )

    /**
     * Parses an ISO 8601 timestamp, returning null when the value is absent or unparseable.
     */
    fun parse(value: String?): Date? {
        if (value.isNullOrBlank()) return null
        val normalized = normalizeFraction(value.trim())
        for (pattern in PATTERNS) {
            // SimpleDateFormat is not thread-safe; create per call
            val format = SimpleDateFormat(pattern, Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
                isLenient = false
            }
            try {
                return format.parse(normalized)
            } catch (_: ParseException) {
                // Try the next pattern
            }
        }
        return null
    }

    /** Truncates or pads fractional seconds to exactly three digits (milliseconds). */
    private fun normalizeFraction(value: String): String {
        val match = FRACTION.find(value) ?: return value
        val millis = match.groupValues[1].take(3).padEnd(3, '0')
        return value.replaceRange(match.range, ".$millis")
    }
}
