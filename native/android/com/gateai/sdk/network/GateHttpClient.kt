package com.gateai.sdk.network

import com.gateai.sdk.core.GateAIConfiguration
import com.gateai.sdk.core.HttpMethod
import com.gateai.sdk.logging.GateLogger
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.headers
import io.ktor.client.request.post
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.request.url
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpMethod as KtorHttpMethod
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.isSuccess
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json

class GateHttpClient(
    private val configuration: GateAIConfiguration,
    private val logger: GateLogger
) {
    private val client = HttpClient(OkHttp) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                // Emit literal fields that have Kotlin defaults (platform, type) —
                // the server's schema discriminates on them
                encodeDefaults = true
                // But never send "field": null for absent optionals
                explicitNulls = false
            })
        }

        defaultRequest {
            url(configuration.baseUrl)
            headers {
                append(HttpHeaders.Accept, ContentType.Application.Json.toString())
                append("X-GateAI-Package", configuration.packageName)
            }
        }
    }

    suspend fun <T> post(
        path: String,
        body: Any,
        responseType: KSerializer<T>,
        dpop: String? = null
    ): T {
        logger.debug("POST $path")
        val response: HttpResponse = client.post {
            url(path)
            headers {
                append(HttpHeaders.ContentType, ContentType.Application.Json.toString())
                dpop?.let { append("DPoP", it) }
            }
            setBody(body)
        }

        logger.debug("Response ${response.status}")
        if (!response.status.isSuccess()) {
            val responseBody = response.bodyAsText()
            val headers = response.headers.entries().associate { it.key to it.value.joinToString() }
            throw GateApiException(response.status.value, headers, responseBody)
        }

        val responseText = response.bodyAsText()
        return Json.decodeFromString(responseType, responseText)
    }

    suspend fun postRaw(
        method: HttpMethod,
        path: String,
        body: Any?,
        headers: Map<String, String>
    ): RawResponse {
        logger.debug("${method.value} $path (raw)")
        val response = client.request {
            this.method = method.toKtor()
            url(path)
            headers.forEach { (key, value) -> this.headers.append(key, value) }
            if (body != null) {
                setBody(body)
            }
        }

        val responseBody = response.bodyAsText()
        val responseHeaders = response.headers.entries().associate { it.key to it.value.joinToString() }

        if (!response.status.isSuccess()) {
            throw GateApiException(response.status.value, responseHeaders, responseBody)
        }

        return RawResponse(
            status = response.status.value,
            headers = responseHeaders,
            body = responseBody
        )
    }

    private fun HttpMethod.toKtor(): KtorHttpMethod = when (this) {
        HttpMethod.GET -> KtorHttpMethod.Get
        HttpMethod.POST -> KtorHttpMethod.Post
        HttpMethod.PUT -> KtorHttpMethod.Put
        HttpMethod.DELETE -> KtorHttpMethod.Delete
        HttpMethod.PATCH -> KtorHttpMethod.Patch
    }
}

data class RawResponse(
    val status: Int,
    val headers: Map<String, String>,
    val body: String?
) {
    /**
     * Remaining device quota parsed from the `X-Quota-*` response headers,
     * or null when the gate has no device usage limits configured.
     *
     * ## Example
     *
     * ```kotlin
     * response.quotaStatus?.let { quota ->
     *     // e.g., "${quota.requestsRemaining} requests left"
     * }
     * ```
     */
    val quotaStatus: QuotaStatus?
        get() = QuotaStatus.fromHeaders(headers)
}

