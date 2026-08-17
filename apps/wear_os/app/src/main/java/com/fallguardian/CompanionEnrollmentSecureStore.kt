package com.fallguardian

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Durable, Android Keystore-backed storage for the watch's own device
 * credentials, obtained once by claiming a companion-enrollment token from
 * the phone. Per docs/COMPANION_ENROLLMENT.md §3: `deviceToken` is a durable
 * secret and is AES/GCM-encrypted with a Keystore-bound key before it ever
 * touches disk; `deviceId` and schema version are non-sensitive and are
 * stored alongside it in the same private preferences file.
 *
 * Mirrors AndroidSecureStore.kt in apps/assisted_mobile/android — same
 * technique (raw AndroidKeyStore + AES/GCM), kept as a separate class
 * because this is a different app/module with its own Keystore alias.
 */
data class CompanionCredentials(val deviceId: String, val deviceToken: String)

class CompanionEnrollmentSecureStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(
        PREFS_NAME,
        Context.MODE_PRIVATE
    )

    fun read(): CompanionCredentials? {
        val deviceId = prefs.getString(DEVICE_ID_KEY, null) ?: return null
        val encryptedToken = prefs.getString(DEVICE_TOKEN_KEY, null) ?: return null
        val deviceToken = try {
            decrypt(encryptedToken)
        } catch (error: Exception) {
            Log.e(TAG, "Unable to decrypt companion device token", error)
            clear()
            return null
        }
        return CompanionCredentials(deviceId, deviceToken)
    }

    fun save(deviceId: String, deviceToken: String, schemaVersion: Int) {
        prefs.edit()
            .putString(DEVICE_ID_KEY, deviceId)
            .putString(DEVICE_TOKEN_KEY, encrypt(deviceToken))
            .putInt(SCHEMA_VERSION_KEY, schemaVersion)
            .putLong(ENROLLED_AT_KEY, System.currentTimeMillis())
            .apply()
    }

    fun clear() {
        prefs.edit()
            .remove(DEVICE_ID_KEY)
            .remove(DEVICE_TOKEN_KEY)
            .remove(SCHEMA_VERSION_KEY)
            .remove(ENROLLED_AT_KEY)
            .apply()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val encrypted = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        return Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(encrypted, Base64.NO_WRAP)
    }

    private fun decrypt(payload: String): String {
        val parts = payload.split(":")
        require(parts.size == 2) { "Invalid secure payload" }
        val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateSecretKey(),
            GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP))
        )
        val decrypted = cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP))
        return String(decrypted, StandardCharsets.UTF_8)
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private companion object {
        const val TAG = "CompanionEnrollment"
        const val PREFS_NAME = "fall_guardian_companion"
        const val KEY_ALIAS = "fall_guardian_companion_device_token"
        const val DEVICE_ID_KEY = "device_id"
        const val DEVICE_TOKEN_KEY = "device_token"
        const val SCHEMA_VERSION_KEY = "schema_version"
        const val ENROLLED_AT_KEY = "enrolled_at"
        const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
