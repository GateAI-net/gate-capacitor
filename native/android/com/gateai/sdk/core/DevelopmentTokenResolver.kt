package com.gateai.sdk.core

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.res.Resources

/** Resolves an optional host-app token without reading secrets in non-debuggable apps. */
internal object DevelopmentTokenResolver {
    private const val RESOURCE_NAME = "gate_ai_dev_token"

    fun resolve(context: Context, configuredToken: String?): String? = resolve(
        isDebuggable = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0,
        configuredToken = configuredToken
    ) {
        val id = context.resources.getIdentifier(RESOURCE_NAME, "string", context.packageName)
        if (id == 0) null else try {
            context.getString(id)
        } catch (_: Resources.NotFoundException) {
            null
        }
    }

    internal fun resolve(
        isDebuggable: Boolean,
        configuredToken: String?,
        resourceToken: () -> String?
    ): String? {
        if (!isDebuggable) return null
        // Keep explicit configuration compatible with existing integrations.
        return configuredToken?.takeIf { it.isNotBlank() }
            ?: resourceToken()?.takeIf { it.isNotBlank() }
    }
}
