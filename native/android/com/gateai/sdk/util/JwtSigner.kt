package com.gateai.sdk.util

class JwtSigner(
    private val signer: suspend (ByteArray) -> ByteArray
) {
    suspend fun sign(header: Map<String, Any?>, payload: Map<String, Any?>): String {
        val encodedHeader = Base64Url.encode(header.toCanonicalJson().toByteArray())
        val encodedPayload = Base64Url.encode(payload.toCanonicalJson().toByteArray())

        val signingInput = "$encodedHeader.$encodedPayload"
        val signature = signer(signingInput.toByteArray())
        val encodedSignature = Base64Url.encode(signature)

        return "$signingInput.$encodedSignature"
    }
}

private fun Map<String, Any?>.toCanonicalJson(): String {
    return buildString {
        append('{')
        val iterator = this@toCanonicalJson.entries.sortedBy { it.key }.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            append('"').append(entry.key).append('"').append(':')
            append(entry.value.toJsonValue())
            if (iterator.hasNext()) append(',')
        }
        append('}')
    }
}

private fun Any?.toJsonValue(): String = when (this) {
    null -> "null"
    is String -> "\"${this.replace("\"", "\\\"")}\""
    is Number, is Boolean -> toString()
    is Map<*, *> -> {
        @Suppress("UNCHECKED_CAST")
        (this as Map<String, Any?>).toCanonicalJson()
    }
    else -> throw IllegalArgumentException("Unsupported JSON value type: ${this::class}")
}

