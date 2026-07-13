package com.geqian.flyplayer.fly_player

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale

class ExternalLocalVideoActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleExternalOpen(intent)
    }

    private fun handleExternalOpen(sourceIntent: Intent?) {
        val uri = resolveSingleUri(sourceIntent)
        if (uri == null) {
            reject("Fly Player only supports opening one video file at a time")
            return
        }
        val scheme = uri.scheme?.lowercase(Locale.US).orEmpty()
        if (scheme != "content" && scheme != "file") {
            reject("Fly Player only supports local video files")
            return
        }

        val displayName = queryDisplayName(uri).ifBlank { "Local Video" }
        if (!isSupportedVideoUri(sourceIntent, uri, displayName)) {
            reject("Fly Player can only open video files")
            return
        }
        if (!canReadUri(uri)) {
            reject("Fly Player cannot read this video file")
            return
        }

        val loadArgs = PlayerLaunchContract.buildExternalLocalVideoLoadArgs(
            uri = uri,
            title = displayName,
            sizeBytes = querySizeBytes(uri),
        )
        val launchIntent = Intent(this, NativePlayerActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            putExtra(NativePlayerActivity.EXTRA_LOAD_ARGS, loadArgsToJson(loadArgs))
            if (!sourceIntent?.type.isNullOrBlank()) {
                setDataAndType(uri, sourceIntent?.type)
            } else {
                data = uri
            }
            clipData = ClipData.newUri(contentResolver, displayName, uri)
        }
        runCatching {
            startActivity(launchIntent)
        }.onFailure {
            reject("Fly Player failed to open this video")
            return
        }
        finish()
        overridePendingTransition(0, 0)
    }

    private fun loadArgsToJson(loadArgs: Map<String, Any?>): String {
        return jsonValue(loadArgs).toString()
    }

    private fun jsonValue(value: Any?): Any {
        return when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> JSONObject().apply {
                value.forEach { (key, nestedValue) ->
                    if (key != null) put(key.toString(), jsonValue(nestedValue))
                }
            }
            is Iterable<*> -> JSONArray().apply {
                value.forEach { put(jsonValue(it)) }
            }
            is Array<*> -> JSONArray().apply {
                value.forEach { put(jsonValue(it)) }
            }
            else -> value
        }
    }

    private fun resolveSingleUri(intent: Intent?): Uri? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        val dataUri = intent.data
        val clipData = intent.clipData
        if (clipData != null) {
            if (clipData.itemCount != 1) return null
            val clipUri = clipData.getItemAt(0)?.uri ?: return null
            if (dataUri != null && dataUri != clipUri) return null
            return clipUri
        }
        return dataUri
    }

    private fun isSupportedVideoUri(
        intent: Intent?,
        uri: Uri,
        displayName: String,
    ): Boolean {
        val mimeTypes = listOf(
            intent?.type.orEmpty(),
            runCatching { contentResolver.getType(uri).orEmpty() }.getOrDefault(""),
        ).map { it.trim().lowercase(Locale.US) }
            .filter { it.isNotEmpty() }
        if (mimeTypes.any { it.startsWith("video/") }) {
            return true
        }
        val reliableMime = mimeTypes.firstOrNull { it != "*/*" && it != "application/octet-stream" }
        if (reliableMime != null) {
            return false
        }
        return videoExtensions.contains(extensionOf(displayName).ifBlank { extensionOf(uri.toString()) })
    }

    private fun canReadUri(uri: Uri): Boolean {
        return when (uri.scheme?.lowercase(Locale.US)) {
            "file" -> {
                val file = File(uri.path.orEmpty())
                file.isFile && file.canRead()
            }
            "content" -> {
                runCatching {
                    val assetDescriptor = contentResolver.openAssetFileDescriptor(uri, "r")
                    if (assetDescriptor != null) {
                        assetDescriptor.close()
                        return true
                    }
                    val descriptor = contentResolver.openFileDescriptor(uri, "r")
                    if (descriptor != null) {
                        descriptor.close()
                        return true
                    }
                    false
                }.getOrDefault(false)
            }
            else -> false
        }
    }

    private fun queryDisplayName(uri: Uri): String {
        if (uri.scheme.equals("content", ignoreCase = true)) {
            queryOpenableColumn(uri, OpenableColumns.DISPLAY_NAME)?.let { name ->
                if (name.isNotBlank()) return sanitizeDisplayName(name)
            }
        }
        if (uri.scheme.equals("file", ignoreCase = true)) {
            File(uri.path.orEmpty()).name.takeIf { it.isNotBlank() }?.let {
                return sanitizeDisplayName(it)
            }
        }
        return sanitizeDisplayName(uri.lastPathSegment.orEmpty())
    }

    private fun querySizeBytes(uri: Uri): Long {
        if (uri.scheme.equals("file", ignoreCase = true)) {
            return File(uri.path.orEmpty()).length().coerceAtLeast(0L)
        }
        val raw = queryOpenableColumn(uri, OpenableColumns.SIZE) ?: return 0L
        return raw.toLongOrNull()?.coerceAtLeast(0L) ?: 0L
    }

    private fun queryOpenableColumn(uri: Uri, column: String): String? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, arrayOf(column), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(column)
                if (index >= 0) cursor.getString(index) else null
            } else {
                null
            }
        } catch (_: Throwable) {
            null
        } finally {
            cursor?.close()
        }
    }

    private fun sanitizeDisplayName(value: String): String {
        return value.trim().substringAfterLast('/').substringAfterLast('\\')
    }

    private fun extensionOf(value: String): String {
        val name = value.substringBefore('?').substringBefore('#')
        val dotIndex = name.lastIndexOf('.')
        if (dotIndex < 0 || dotIndex >= name.length - 1) return ""
        return name.substring(dotIndex + 1).lowercase(Locale.US)
    }

    private fun reject(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        finish()
        overridePendingTransition(0, 0)
    }

    companion object {
        private val videoExtensions = setOf(
            "mp4",
            "m4v",
            "mkv",
            "webm",
            "avi",
            "mov",
            "wmv",
            "flv",
            "ts",
            "m2ts",
            "mts",
            "3gp",
            "3g2",
            "mpg",
            "mpeg",
            "ogv",
            "rm",
            "rmvb",
            "vob",
            "asf",
            "f4v",
        )
    }
}
