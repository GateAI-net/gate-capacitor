package com.gateai.sdk.security

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.gateai.sdk.core.DeviceKeyJwk
import com.gateai.sdk.util.Base64Url
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.ECGenParameterSpec
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

data class DeviceKeyMaterial(
    val privateKey: PrivateKey,
    val publicKey: PublicKey,
    val jwk: DeviceKeyJwk,
    val thumbprint: String
)

class DeviceKeyManager private constructor(
    private val context: Context,
    private val alias: String
) {

    private val lock = ReentrantLock()

    fun ensureKey(): DeviceKeyMaterial = lock.withLock {
        val keyPair = loadExistingKeyPair() ?: createKeyPair()
        val jwk = keyPair.public.toJwk()
        val thumbprint = jwk.toThumbprint()
        return DeviceKeyMaterial(
            privateKey = keyPair.private,
            publicKey = keyPair.public,
            jwk = jwk,
            thumbprint = thumbprint
        )
    }

    private fun loadExistingKeyPair(): KeyPair? {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        val privateKey = keyStore.getKey(alias, null) as? PrivateKey ?: return null
        val publicKey = keyStore.getCertificate(alias)?.publicKey ?: return null
        return KeyPair(publicKey, privateKey)
    }

    private fun createKeyPair(): KeyPair {
        val keyPairGenerator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,
            ANDROID_KEYSTORE
        )

        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_SIGN
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(false)
            .setInvalidatedByBiometricEnrollment(false)

        // StrongBox is only available on API 28+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(isStrongBoxBackedAvailable())
        }

        val parameterSpec = builder.build()

        keyPairGenerator.initialize(parameterSpec)
        return keyPairGenerator.generateKeyPair()
    }

    private fun isStrongBoxBackedAvailable(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && context.packageManager.hasSystemFeature(
            "android.hardware.strongbox_keystore"
        )
    }

    private fun PublicKey.toJwk(): DeviceKeyJwk {
        val ecPoint = this.encoded.takeLast(65).toByteArray()
        require(ecPoint.first() == 0x04.toByte()) { "Unsupported EC key format" }

        val x = ecPoint.copyOfRange(1, 33)
        val y = ecPoint.copyOfRange(33, 65)

        return DeviceKeyJwk(
            x = Base64Url.encode(x),
            y = Base64Url.encode(y)
        )
    }

    private fun DeviceKeyJwk.toThumbprint(): String {
        val canonical = "{\"crv\":\"$crv\",\"kty\":\"$kty\",\"x\":\"$x\",\"y\":\"$y\"}"
        val digest = MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray())
        return Base64Url.encode(digest)
    }

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val PREFS_NAME = "gateai_device_key"
        private const val PREF_KEY_ALIAS = "alias"

        fun create(context: Context, alias: String = "gateai_dpop_key"): DeviceKeyManager {
            val applicationContext = context.applicationContext
            persistAlias(applicationContext, alias)
            return DeviceKeyManager(applicationContext, alias)
        }

        private fun persistAlias(context: Context, alias: String) {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            val prefs = EncryptedSharedPreferences.create(
                context,
                PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )

            prefs.edit().putString(PREF_KEY_ALIAS, alias).apply()
        }
    }
}

