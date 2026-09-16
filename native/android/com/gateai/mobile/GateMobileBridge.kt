package com.gateai.mobile

import android.content.Context
import com.gateai.sdk.core.GateAIClient
import com.gateai.sdk.core.GateAIConfiguration
import com.gateai.sdk.core.HttpMethod
import com.gateai.sdk.network.GateApiException
import kotlinx.coroutines.CancellationException
import org.json.JSONObject
import java.net.URI
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

internal class GateMobileBridge(private val context: Context) {
    private val clients = ConcurrentHashMap<String, GateAIClient>()

    suspend fun execute(payload: String): String = try {
        JSONObject().put("result", dispatch(JSONObject(payload))).toString()
    } catch (e: CancellationException) {
        throw e
    } catch (e: GateApiException) {
        failure("http", "HTTP ${e.statusCode}", e.statusCode, e.headers, e.body)
    } catch (e: IllegalArgumentException) {
        failure("configuration", e.message ?: "Invalid configuration.")
    } catch (e: Exception) {
        failure("native", e.message ?: "Native Gate/AI operation failed.")
    }

    private suspend fun dispatch(args: JSONObject): Any {
        val operation = args.getString("operation")
        if (operation == "configure") {
            val config = args.getJSONObject("configuration")
            val android = config.optJSONObject("android") ?: error("Android configuration is required on Android.")
            val base = config.getString("baseUrl")
            val uri = URI(base)
            require(uri.scheme == "https" && uri.host != null && uri.userInfo == null && uri.query == null && uri.fragment == null && (uri.path.isNullOrEmpty() || uri.path == "/")) { "baseUrl must be an HTTPS origin." }
            val fingerprint = android.getString("signingCertSha256")
            require(fingerprint.replace(":", "").matches(Regex("^[0-9a-fA-F]{64}$"))) { "Invalid signing certificate fingerprint." }
            val project = android.stringOrNull("cloudProjectNumber")
            require(project == null || project.matches(Regex("^[1-9][0-9]{0,17}$"))) { "Invalid cloudProjectNumber." }
            val configuration = GateAIConfiguration(
                baseUrl = base, packageName = context.packageName, signingCertSha256 = fingerprint,
                cloudProjectNumber = project?.toLong(), developmentToken = android.stringOrNull("developmentToken"),
                deviceIdentifierEnabled = android.optBoolean("deviceIdentifierEnabled", false),
                logLevel = GateAIConfiguration.LogLevel.OFF
            )
            val id = UUID.randomUUID().toString()
            clients[id] = GateAIClient.create(context.applicationContext, configuration)
            return JSONObject().put("clientId", id)
        }
        val id = args.getString("clientId")
        val client = requireNotNull(clients[id]) { "Unknown or disposed client." }
        when (operation) {
            "dispose" -> { clients.remove(id); return JSONObject.NULL }
            "clearCachedState" -> { client.clearCachedState(); return JSONObject.NULL }
            "request", "authorizationHeaders" -> {
                val path = args.getString("path")
                require(path.matches(Regex("^[A-Za-z0-9_~-]+(?:/[A-Za-z0-9_~.-]+)*$")) && path.split('/').none { it == "." || it == ".." }) { "Invalid relative path." }
                val method = HttpMethod.valueOf(args.getString("method"))
                require(method == HttpMethod.GET || method == HttpMethod.POST) { "Only GET and POST are supported." }
                val rawHeaders = args.optJSONObject("headers") ?: JSONObject()
                val headers = rawHeaders.keys().asSequence().associateWith { rawHeaders.getString(it) }
                headers.forEach { (name, value) ->
                    require(name.lowercase() !in listOf("authorization", "dpop", "host", "content-length", "connection") && name.matches(Regex("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$")) && !value.contains('\r') && !value.contains('\n')) { "Invalid or reserved request header." }
                }
                if (operation == "authorizationHeaders") {
                    val result = client.authorizationHeaders(path, method, args.stringOrNull("nonce")).toMutableMap()
                    headers.forEach { (key, value) ->
                        result.keys.filter { it.equals(key, ignoreCase = true) }.forEach { result.remove(it) }
                        result[key] = value
                    }
                    return JSONObject(result as Map<*, *>)
                }
                val body = args.stringOrNull("body")?.toByteArray(Charsets.UTF_8)
                require(method != HttpMethod.GET || body == null) { "GET cannot have a body." }
                val response = client.performProxyRequest(path, method, body, headers)
                return JSONObject().put("status", response.status).put("headers", JSONObject(response.headers as Map<*, *>)).put("body", response.body ?: "")
            }
            else -> throw IllegalArgumentException("Unknown operation.")
        }
    }

    private fun failure(code: String, message: String, status: Int? = null, headers: Map<String, String> = emptyMap(), body: String? = null): String =
        JSONObject().put("error", JSONObject().put("code", code).put("message", message)
            .put("status", status ?: JSONObject.NULL).put("headers", JSONObject(headers as Map<*, *>))
            .put("body", body ?: JSONObject.NULL)).toString()

    private fun JSONObject.stringOrNull(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null
}
