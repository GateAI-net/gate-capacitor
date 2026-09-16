package com.gateai.sdk.playintegrity

import android.content.Context
import com.gateai.sdk.logging.GateLogger
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.tasks.Tasks
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.IntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class PlayIntegrityManager(
    context: Context,
    private val cloudProjectNumber: Long? = null,
    private val logger: GateLogger? = null
) {
    private val appContext = context.applicationContext
    private val manager = IntegrityManagerFactory.create(appContext)

    suspend fun requestIntegrityToken(nonce: String): String = withContext(Dispatchers.IO) {
        logger?.debug("Requesting Play Integrity token with nonce: ${nonce.take(10)}...")
        
        // Google requires the cloud project number for sideloaded installs
        // (anything not installed via the Play Store). Optional for Play installs.
        val request = IntegrityTokenRequest.builder()
            .setNonce(nonce)
            .apply { cloudProjectNumber?.let { setCloudProjectNumber(it) } }
            .build()

        runCatching {
            Tasks.await(manager.requestIntegrityToken(request)).token()
        }.onFailure { throwable ->
            val errorMessage = getDetailedErrorMessage(throwable)
            logger?.error("Play Integrity request failed: $errorMessage", throwable)
        }.getOrElse { throwable ->
            val detailedMessage = getDetailedErrorMessage(throwable)
            throw IntegrityException(
                "Failed to obtain Play Integrity token: $detailedMessage\n\n" +
                "Common causes:\n" +
                "1. App not linked in Google Play Console (package name + signing cert)\n" +
                "2. Play Integrity API not enabled in Google Cloud Console\n" +
                "3. Google Play Services not available or outdated\n" +
                "4. App not approved for Play Integrity yet\n\n" +
                "For testing, use developmentToken in GateAIConfiguration to bypass Play Integrity.",
                throwable
            )
        }
    }

    private fun getDetailedErrorMessage(throwable: Throwable): String {
        return when (throwable) {
            is ApiException -> {
                val statusCode = throwable.statusCode
                val description = getErrorDescription(statusCode)
                "ApiException (statusCode=$statusCode): $description - ${throwable.message}"
            }
            is StandardIntegrityException -> {
                val errorCode = throwable.errorCode
                val description = getErrorDescription(errorCode)
                "IntegrityException (errorCode=$errorCode): $description - ${throwable.message}"
            }
            else -> {
                throwable.message ?: throwable.javaClass.simpleName
            }
        }
    }

    private fun getErrorDescription(errorCode: Int): String {
        return when (errorCode) {
            // Common error codes based on Play Integrity API documentation
            -1 -> "API not available on this device"
            -2 -> "App not installed via Google Play Store"
            -3 -> "Network error - check internet connection"
            -4 -> "App needs internal integrity"
            -5 -> "Google Play Services not found or outdated"
            -6 -> "Google account required"
            -7 -> "Cannot bind to Google Play services"
            -8 -> "Request is invalid"
            -9 -> "Google servers unavailable"
            -10 -> "Internal error"
            -11 -> "Google Play Store not found or outdated"
            -12 -> "Too many requests"
            -100 -> "Client transient error"
            else -> "Unknown error (see Play Integrity API docs for error code $errorCode)"
        }
    }
}

class IntegrityException(message: String, cause: Throwable? = null) : Exception(message, cause)

