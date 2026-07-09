package com.geqian.flyplayer.fly_player

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecureCredentialStore(private val context: Context) {
    fun read(key: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return ""
        val file = credentialFile(key)
        if (!file.exists()) return ""
        return try {
            val payload = JSONObject(file.readText(StandardCharsets.UTF_8))
            decrypt(
                cipherText = payload.optString("encryptedValue"),
                iv = payload.optString("iv"),
            )
        } catch (_: Exception) {
            file.delete()
            ""
        }
    }

    fun write(
        key: String,
        value: String,
    ): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        if (key.isBlank() || value.isEmpty()) {
            delete(key)
            return true
        }
        val encrypted = encrypt(value)
        val payload =
            JSONObject()
                .put("version", STORAGE_VERSION)
                .put("encryptedValue", encrypted.cipherText)
                .put("iv", encrypted.iv)
        val file = credentialFile(key)
        file.parentFile?.mkdirs()
        file.writeText(payload.toString(), StandardCharsets.UTF_8)
        return true
    }

    fun delete(key: String): Boolean {
        val file = credentialFile(key)
        if (file.exists()) {
            file.delete()
        }
        return true
    }

    private fun credentialFile(key: String): File =
        File(File(context.noBackupFilesDir, STORE_DIR), "${hashKey(key)}.json")

    private fun hashKey(key: String): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest(key.trim().toByteArray(StandardCharsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }

    private fun encrypt(value: String): EncryptionResult {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val cipherText = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        return EncryptionResult(
            cipherText = Base64.encodeToString(cipherText, Base64.NO_WRAP),
            iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
        )
    }

    private fun decrypt(
        cipherText: String,
        iv: String,
    ): String {
        if (cipherText.isBlank() || iv.isBlank()) {
            throw IllegalStateException("Credential payload is incomplete")
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateSecretKey(),
            GCMParameterSpec(GCM_TAG_LENGTH_BITS, Base64.decode(iv, Base64.NO_WRAP)),
        )
        val plainText = cipher.doFinal(Base64.decode(cipherText, Base64.NO_WRAP))
        return String(plainText, StandardCharsets.UTF_8)
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val existingKey = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
        if (existingKey != null) {
            return existingKey
        }
        val generator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        generator.init(
            KeyGenParameterSpec
                .Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        return generator.generateKey()
    }

    private data class EncryptionResult(
        val cipherText: String,
        val iv: String,
    )

    private companion object {
        const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        const val KEY_ALIAS = "fly_player_secure_credential_key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val STORE_DIR = "secure_credentials"
        const val STORAGE_VERSION = 1
        const val GCM_TAG_LENGTH_BITS = 128
    }
}
