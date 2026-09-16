package com.gateai.sdk.logging

import android.util.Log
import com.gateai.sdk.core.GateAIConfiguration

interface GateLogger {
    fun setLogLevel(level: GateAIConfiguration.LogLevel)
    fun debug(message: String)
    fun info(message: String)
    fun warn(message: String)
    fun error(message: String, throwable: Throwable? = null)
}

class AndroidGateLogger(
    private var logLevel: GateAIConfiguration.LogLevel = GateAIConfiguration.LogLevel.INFO
) : GateLogger {

    override fun setLogLevel(level: GateAIConfiguration.LogLevel) {
        logLevel = level
    }

    override fun debug(message: String) {
        if (logLevel >= GateAIConfiguration.LogLevel.DEBUG) {
            Log.d(TAG, message)
        }
    }

    override fun info(message: String) {
        if (logLevel >= GateAIConfiguration.LogLevel.INFO) {
            Log.i(TAG, message)
        }
    }

    override fun warn(message: String) {
        if (logLevel >= GateAIConfiguration.LogLevel.WARN) {
            Log.w(TAG, message)
        }
    }

    override fun error(message: String, throwable: Throwable?) {
        if (logLevel >= GateAIConfiguration.LogLevel.ERROR) {
            Log.e(TAG, message, throwable)
        }
    }

    companion object {
        private const val TAG = "GateAI"
    }
}

private operator fun GateAIConfiguration.LogLevel.compareTo(other: GateAIConfiguration.LogLevel): Int {
    return ordinal.compareTo(other.ordinal)
}


