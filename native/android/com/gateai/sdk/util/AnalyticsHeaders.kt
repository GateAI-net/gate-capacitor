package com.gateai.sdk.util

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.provider.Settings
import com.gateai.sdk.BuildConfig
import java.util.Locale

/**
 * Helper to generate analytics headers for Gate/AI requests.
 *
 * These headers provide contextual information about the app and device for analytics purposes.
 */
internal class AnalyticsHeaders(
    private val context: Context,
    private val userStatus: String? = null,
    private val userTier: String? = null,
    private val userIdentifier: String? = null,
    private val appFeature: String? = null,
    private val quotaAnchorDay: Int? = null,
    private val sendDeviceIdentifier: Boolean = false
) {
    /**
     * Generates a map of analytics headers.
     *
     * @return A map with X-prefixed analytics headers
     */
    fun headers(): Map<String, String> {
        val headers = mutableMapOf<String, String>()

        // X-Client-Locale: Language and country code (e.g., "es-MX", "en-US")
        clientLocale()?.let { headers["X-Client-Locale"] = it }

        // X-App-Version: App version from package (e.g., "1.0.2")
        appVersion()?.let { headers["X-App-Version"] = it }

        // X-OS-Version: Android version (e.g., "14", "13")
        osVersion()?.let { headers["X-OS-Version"] = it }

        // X-User-Status: Custom status provided by developer
        userStatus?.let { headers["X-User-Status"] = it }

        // X-User-Tier: Plan tier provided by developer; matched exactly (case-sensitive)
        // against Portal-configured per-tier usage limits
        userTier?.let { headers["X-User-Tier"] = it }

        // X-User-Identifier: Opaque user/account ID provided by developer (no PII)
        userIdentifier?.let { headers["X-User-Identifier"] = it }

        // X-App-Feature: Feature tag for cost attribution provided by developer (e.g., "chat")
        appFeature?.let { headers["X-App-Feature"] = it }

        // X-Quota-Anchor-Day: Day-of-month the user's subscription renews (1-31),
        // provided by developer; anchors billing-cycle device usage windows
        quotaAnchorDay?.let { headers["X-Quota-Anchor-Day"] = it.toString() }

        // X-Environment: "development" for debuggable builds, "production" otherwise
        environment()?.let { headers["X-Environment"] = it }

        // X-Device-Identifier: Android ID (unique per-app, per-device identifier).
        // Opt-in only — persistent device identifiers carry a disclosure obligation.
        if (sendDeviceIdentifier) {
            deviceIdentifier()?.let { headers["X-Device-Identifier"] = it }
        }

        // X-Device-Type: Device model (e.g., "Pixel 8", "Samsung Galaxy S23")
        deviceType()?.let { headers["X-Device-Type"] = it }

        // X-Device-Model: Raw hardware model identifier (e.g., "SM-G991U")
        deviceModel()?.let { headers["X-Device-Model"] = it }

        // X-SDK-Version: Gate/AI SDK version (e.g., "1.1.0")
        sdkVersion()?.let { headers["X-SDK-Version"] = it }

        return headers
    }

    private fun clientLocale(): String? {
        return try {
            // Convert "en_US" to "en-US" format
            Locale.getDefault().toString().replace("_", "-")
        } catch (e: Exception) {
            null
        }
    }

    private fun appVersion(): String? {
        return try {
            val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
            packageInfo.versionName
        } catch (e: Exception) {
            null
        }
    }

    private fun osVersion(): String? {
        return try {
            Build.VERSION.RELEASE
        } catch (e: Exception) {
            null
        }
    }

    private fun environment(): String? {
        return try {
            val debuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            if (debuggable) "development" else "production"
        } catch (e: Exception) {
            null
        }
    }

    private fun deviceModel(): String? {
        return try {
            // Raw hardware model identifier, e.g. "SM-G991U"
            Build.MODEL
        } catch (e: Exception) {
            null
        }
    }

    private fun sdkVersion(): String? {
        return try {
            BuildConfig.SDK_VERSION
        } catch (e: Exception) {
            null
        }
    }

    private fun deviceIdentifier(): String? {
        return try {
            // Android ID is a unique identifier per-app, per-device
            // It's reset on factory reset and stable across app reinstalls
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        } catch (e: Exception) {
            null
        }
    }

    private fun deviceType(): String? {
        return try {
            // Returns something like "Pixel 8" or "Samsung SM-G991U"
            val manufacturer = Build.MANUFACTURER
            val model = Build.MODEL
            if (model.startsWith(manufacturer, ignoreCase = true)) {
                model.capitalize(Locale.ROOT)
            } else {
                "${manufacturer.capitalize(Locale.ROOT)} $model"
            }
        } catch (e: Exception) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun String.capitalize(locale: Locale): String {
        return this.replaceFirstChar {
            if (it.isLowerCase()) it.titlecase(locale) else it.toString()
        }
    }
}

