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
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class DanDanPlaySecretStore(private val context: Context) {
    private data class StoredConfig(
        val appId: String,
        val appSecrets: List<String>,
    )

    fun getConfig(): HashMap<String, Any> {
        bootstrapIfNeeded()
        val stored = loadStoredConfig()
        if (stored != null) {
            return hashMapOf(
                "appId" to stored.appId,
                "appSecrets" to ArrayList(stored.appSecrets),
                "configured" to true,
                "statusCode" to "",
                "statusMessage" to "",
            )
        }
        return hashMapOf(
            "appId" to "",
            "appSecrets" to arrayListOf<String>(),
            "configured" to false,
            "statusCode" to unavailableCode(),
            "statusMessage" to "",
        )
    }

    fun clearConfig(): Boolean {
        if (configFile.exists()) {
            configFile.delete()
        }
        return true
    }

    private val configFile: File
        get() = File(context.noBackupFilesDir, CONFIG_FILE_NAME)

    private fun unavailableCode(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return STATUS_UNSUPPORTED_ANDROID_VERSION
        }
        return STATUS_MISSING_BUILD_CREDENTIALS
    }

    private fun bootstrapIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }
        val buildConfig = readInjectedBuildConfig() ?: return
        if (configFile.exists()) {
            // 自愈：缓存凭据与当前 BuildConfig 一致就沿用；不一致（如曾用错误密钥构建运行过，
            // 旧值已加密落盘）则删旧缓存按当前 BuildConfig 重建，避免旧错值一直被使用导致签名失败。
            val stored = loadStoredConfig(allowRebootstrap = false)
            if (stored != null &&
                stored.appId == buildConfig.appId &&
                stored.appSecrets == buildConfig.appSecrets
            ) {
                return
            }
            clearConfig()
        }
        val encryptedAppId = encrypt(buildConfig.appId)
        val payload =
            JSONObject()
                .put("version", STORAGE_VERSION)
                .put("encryptedAppId", encryptedAppId.cipherText)
                .put("ivAppId", encryptedAppId.iv)
        buildConfig.appSecrets.forEachIndexed { index, secret ->
            val encryptedSecret = encrypt(secret)
            val suffix = if (index == 0) "" else index.toString()
            payload
                .put("encryptedSecret$suffix", encryptedSecret.cipherText)
                .put("ivSecret$suffix", encryptedSecret.iv)
        }
        configFile.parentFile?.mkdirs()
        configFile.writeText(payload.toString(), StandardCharsets.UTF_8)
    }

    private fun loadStoredConfig(allowRebootstrap: Boolean = true): StoredConfig? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return null
        }
        if (!configFile.exists()) {
            return null
        }
        return try {
            val payload = JSONObject(configFile.readText(StandardCharsets.UTF_8))
            val appId =
                decrypt(
                    cipherText = payload.optString("encryptedAppId"),
                    iv = payload.optString("ivAppId"),
                )
            val appSecret =
                decrypt(
                    cipherText = payload.optString("encryptedSecret"),
                    iv = payload.optString("ivSecret"),
                )
            val fallbackSecret =
                decryptOrNull(
                    cipherText = payload.optString("encryptedSecret1"),
                    iv = payload.optString("ivSecret1"),
                )
            val appSecrets =
                listOfNotNull(
                    appSecret.takeIf { it.isNotBlank() },
                    fallbackSecret?.takeIf { it.isNotBlank() },
                )
            if (appId.isBlank() || appSecrets.isEmpty()) {
                throw IllegalStateException("DanDanPlay config is empty")
            }
            StoredConfig(appId = appId, appSecrets = appSecrets)
        } catch (_: Exception) {
            clearConfig()
            if (!allowRebootstrap) {
                null
            } else {
                bootstrapIfNeeded()
                loadStoredConfig(allowRebootstrap = false)
            }
        }
    }

    private fun readInjectedBuildConfig(): StoredConfig? {
        val appId = BuildConfig.DANDANPLAY_APP_ID.trim()
        val appSecret = BuildConfig.DANDANPLAY_APP_SECRET.trim()
        val fallbackSecret = BuildConfig.DANDANPLAY_APP_SECRET_FALLBACK.trim()
        val appSecrets =
            listOfNotNull(
                appSecret.takeIf { it.isNotEmpty() },
                fallbackSecret.takeIf { it.isNotEmpty() },
            )
        if (appId.isEmpty() || appSecrets.isEmpty()) {
            return null
        }
        return StoredConfig(appId = appId, appSecrets = appSecrets)
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
            throw IllegalStateException("DanDanPlay config is incomplete")
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        val ivBytes = Base64.decode(iv, Base64.NO_WRAP)
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateSecretKey(),
            GCMParameterSpec(GCM_TAG_LENGTH_BITS, ivBytes),
        )
        val plainText = cipher.doFinal(Base64.decode(cipherText, Base64.NO_WRAP))
        return String(plainText, StandardCharsets.UTF_8)
    }

    private fun decryptOrNull(
        cipherText: String,
        iv: String,
    ): String? {
        if (cipherText.isBlank() || iv.isBlank()) {
            return null
        }
        return decrypt(cipherText = cipherText, iv = iv)
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
        const val KEY_ALIAS = "fly_player_dandanplay_config_key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val CONFIG_FILE_NAME = "dandanplay_secure_config.json"
        const val STORAGE_VERSION = 1
        const val GCM_TAG_LENGTH_BITS = 128
        const val STATUS_MISSING_BUILD_CREDENTIALS = "missing_build_credentials"
        const val STATUS_UNSUPPORTED_ANDROID_VERSION = "unsupported_android_version"
    }
}
