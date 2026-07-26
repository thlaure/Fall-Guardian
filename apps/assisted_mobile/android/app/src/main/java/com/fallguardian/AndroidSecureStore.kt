package com.fallguardian

import android.content.Context
import android.util.Base64
import android.util.Log
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore-backed storage shared by Flutter and native background jobs.
 *
 * The Flutter secure-storage MethodChannel and NativeAlertRelayJobService must
 * read the exact same device token. Keeping the crypto implementation here
 * avoids copying credentials into an additional plaintext preference.
 */
internal class AndroidSecureStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(
        MainActivity.PREFS_NAME,
        Context.MODE_PRIVATE
    )

    fun read(key: String): String? {
        val encoded = prefs.getString(SECURE_STORE_PREFIX + key, null) ?: return null
        return try {
            decrypt(encoded)
        } catch (error: Exception) {
            Log.e(TAG, "Unable to decrypt secure value for $key", error)
            prefs.edit().remove(SECURE_STORE_PREFIX + key).apply()
            null
        }
    }

    fun write(key: String, value: String) {
        prefs.edit()
            .putString(SECURE_STORE_PREFIX + key, encrypt(value))
            .apply()
    }

    fun delete(key: String) {
        prefs.edit().remove(SECURE_STORE_PREFIX + key).apply()
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
        val existing = keyStore.getKey(SECURE_STORE_KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                SECURE_STORE_KEY_ALIAS,
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
        const val TAG = "AndroidSecureStore"
        const val SECURE_STORE_KEY_ALIAS = "fall_guardian_secure_store"
        const val SECURE_STORE_PREFIX = "secure:"
        const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
