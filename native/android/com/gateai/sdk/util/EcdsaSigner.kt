package com.gateai.sdk.util

import java.security.PrivateKey
import java.security.Signature

object EcdsaSigner {
    fun sign(privateKey: PrivateKey, data: ByteArray): ByteArray {
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initSign(privateKey)
        signature.update(data)
        val der = signature.sign()
        return derToConcat(der)
    }

    private fun derToConcat(der: ByteArray): ByteArray {
        // Basic DER parser for ECDSA signature
        if (der.size < 8 || der[0] != 0x30.toByte()) {
            throw IllegalArgumentException("Invalid DER signature format")
        }

        var offset = 2
        if ((der[1].toInt() and 0x80) != 0) {
            val lengthBytes = der[1].toInt() and 0x7F
            offset += lengthBytes
        }

        if (der[offset] != 0x02.toByte()) {
            throw IllegalArgumentException("Invalid DER signature format: missing R")
        }
        val rLength = der[offset + 1].toInt()
        val rStart = offset + 2
        offset = rStart + rLength

        if (der[offset] != 0x02.toByte()) {
            throw IllegalArgumentException("Invalid DER signature format: missing S")
        }
        val sLength = der[offset + 1].toInt()
        val sStart = offset + 2

        val r = der.copyOfRange(rStart, rStart + rLength).stripLeadingZeros()
        val s = der.copyOfRange(sStart, sStart + sLength).stripLeadingZeros()

        return r.padTo(32) + s.padTo(32)
    }

    private fun ByteArray.stripLeadingZeros(): ByteArray {
        var index = 0
        while (index < size - 1 && this[index] == 0.toByte()) {
            index++
        }
        return copyOfRange(index, size)
    }

    private fun ByteArray.padTo(length: Int): ByteArray {
        if (size == length) return this
        require(size < length) { "Signature component longer than expected" }
        val padded = ByteArray(length)
        copyInto(padded, destinationOffset = length - size)
        return padded
    }
}

private infix fun Byte.and(other: Byte): Byte = (toInt() and other.toInt()).toByte()

