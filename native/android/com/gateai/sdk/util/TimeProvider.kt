package com.gateai.sdk.util

interface TimeProvider {
    fun currentTimeSeconds(): Long
}

class SystemTimeProvider : TimeProvider {
    override fun currentTimeSeconds(): Long = System.currentTimeMillis() / 1000
}

