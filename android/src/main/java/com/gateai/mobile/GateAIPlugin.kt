package com.gateai.mobile

import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import kotlinx.coroutines.*

@CapacitorPlugin(name = "GateAI")
class GateAIPlugin : Plugin() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private lateinit var implementation: GateMobileBridge
    override fun load() { implementation = GateMobileBridge(context) }
    @PluginMethod
    fun execute(call: PluginCall) {
        val payload = call.getString("payload") ?: run { call.reject("Missing payload."); return }
        scope.launch {
            try { call.resolve(JSObject().put("payload", implementation.execute(payload))) }
            catch (e: CancellationException) { call.reject("Native plugin was destroyed."); throw e }
        }
    }
    override fun handleOnDestroy() { scope.cancel(); super.handleOnDestroy() }
}
