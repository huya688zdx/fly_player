package com.geqian.flyplayer.fly_player

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.io.FileInputStream

internal class ScreenshotDirectoryAccessController(
    private val context: Context,
) {
    private val contentResolver: ContentResolver
        get() = context.contentResolver

    fun currentTreeUri(): Uri? {
        val raw = preferences.getString(KEY_TREE_URI, null)?.trim().orEmpty()
        if (raw.isEmpty()) {
            return null
        }
        return runCatching { Uri.parse(raw) }.getOrNull()
    }

    fun currentDirectorySummary(): Map<String, Any?>? {
        val treeUri = currentTreeUri() ?: return null
        val treeName = storedTreeName()
        val rootId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull()
        if (rootId.isNullOrBlank()) {
            return mapOf(
                "id" to "",
                "name" to treeName.ifBlank { context.getString(R.string.screenshot_selected_directory) },
                "locationLabel" to treeName.ifBlank { context.getString(R.string.screenshot_custom_directory) },
                "available" to false,
            )
        }
        val available = hasPersistedReadPermission(treeUri)
        val resolvedName =
            if (available) {
                queryDirectoryName(treeUri, rootId).ifBlank { treeName }
            } else {
                treeName
            }.ifBlank { context.getString(R.string.screenshot_selected_directory) }
        return mapOf(
            "id" to rootId,
            "name" to resolvedName,
            "locationLabel" to resolvedName,
            "available" to available,
        )
    }

    fun persistGrantedTree(
        treeUri: Uri,
        grantFlags: Int,
    ): Map<String, Any?>? {
        val persistedFlags =
            grantFlags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if (persistedFlags != 0) {
            runCatching {
                contentResolver.takePersistableUriPermission(treeUri, persistedFlags)
            }
        }
        val rootId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull()
        val treeName =
            if (!rootId.isNullOrBlank()) {
                queryDirectoryName(treeUri, rootId)
            } else {
                ""
            }
        preferences
            .edit()
            .putString(KEY_TREE_URI, treeUri.toString())
            .putString(KEY_TREE_NAME, treeName)
            .apply()
        return currentDirectorySummary()
    }

    fun listImageEntries(): List<Map<String, Any?>> {
        val treeUri = currentTreeUri() ?: return emptyList()
        if (!hasPersistedReadPermission(treeUri)) {
            return emptyList()
        }
        val rootId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull()
        if (rootId.isNullOrBlank()) {
            return emptyList()
        }
        val directoryLabel =
            queryDirectoryName(treeUri, rootId).ifBlank {
                storedTreeName().ifBlank { context.getString(R.string.screenshot_custom_directory) }
            }
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, rootId)
        val entries = mutableListOf<Map<String, Any?>>()
        contentResolver
            .query(childrenUri, CHILD_PROJECTION, null, null, null)
            ?.use { cursor ->
                val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeTypeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                while (cursor.moveToNext()) {
                    if (idIndex < 0 || nameIndex < 0 || mimeTypeIndex < 0) {
                        continue
                    }
                    val documentId = cursor.getString(idIndex)?.trim().orEmpty()
                    val displayName = cursor.getString(nameIndex)?.trim().orEmpty()
                    val mimeType = cursor.getString(mimeTypeIndex)?.trim().orEmpty()
                    if (documentId.isEmpty() || displayName.isEmpty()) {
                        continue
                    }
                    if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                        continue
                    }
                    if (!isImageDocument(displayName, mimeType)) {
                        continue
                    }
                    val sizeBytes =
                        if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                            cursor.getLong(sizeIndex)
                        } else {
                            0L
                        }
                    val modifiedAtMs =
                        if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) {
                            cursor.getLong(modifiedIndex)
                        } else {
                            0L
                        }
                    val documentUri =
                        DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
                    val format =
                        ScreenshotImageFormatInspector.inspectUri(
                            contentResolver = contentResolver,
                            uri = documentUri,
                            displayName = displayName,
                            mimeType = mimeType,
                        )
                    entries +=
                        mapOf(
                            "id" to "custom:$documentId",
                            "name" to displayName,
                            "sourceKind" to "custom",
                            "locationLabel" to directoryLabel,
                            "formatKind" to format.formatKind,
                            "isHdr" to format.isHdr,
                            "sizeBytes" to sizeBytes,
                            "modifiedAtMs" to modifiedAtMs,
                            "isScoped" to true,
                            "pathOrIdentifier" to documentId,
                        )
                }
            }
        return entries
    }

    fun readFileBytes(identifier: String): ByteArray? {
        val treeUri = currentTreeUri() ?: return null
        if (!hasPersistedReadPermission(treeUri)) {
            return null
        }
        val documentId = identifier.trim()
        if (documentId.isEmpty()) {
            return null
        }
        val documentUri = documentUri(treeUri, documentId)
        return contentResolver.openInputStream(documentUri)?.use { stream ->
            stream.readBytes()
        }
    }

    fun deleteFile(identifier: String): Boolean {
        val treeUri = currentTreeUri() ?: return false
        if (!hasPersistedWritePermission(treeUri)) {
            return false
        }
        val documentId = identifier.trim()
        if (documentId.isEmpty()) {
            return false
        }
        val documentUri = documentUri(treeUri, documentId)
        return runCatching {
            DocumentsContract.deleteDocument(contentResolver, documentUri)
        }.getOrDefault(false)
    }

    fun saveCapturedFrame(
        tempFile: File,
        displayName: String,
    ): String? {
        val treeUri = currentTreeUri() ?: return null
        if (!hasPersistedWritePermission(treeUri)) {
            return null
        }
        val rootId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull()
        if (rootId.isNullOrBlank()) {
            return null
        }
        val parentUri = documentUri(treeUri, rootId)
        return runCatching {
            val documentUri =
                DocumentsContract.createDocument(
                    contentResolver,
                    parentUri,
                    "image/jpeg",
                    displayName,
                ) ?: return@runCatching null
            contentResolver.openOutputStream(documentUri)?.use { output ->
                FileInputStream(tempFile).use { input ->
                    input.copyTo(output)
                }
            } ?: return@runCatching null
            documentUri.toString()
        }.getOrNull()
    }

    fun clearPersistedTree() {
        val treeUri = currentTreeUri()
        if (treeUri != null) {
            val releasedFlags =
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            runCatching {
                contentResolver.releasePersistableUriPermission(treeUri, releasedFlags)
            }
        }
        preferences.edit().remove(KEY_TREE_URI).remove(KEY_TREE_NAME).apply()
    }

    fun hasConfiguredDirectory(): Boolean = currentTreeUri() != null

    private fun storedTreeName(): String {
        return preferences.getString(KEY_TREE_NAME, null)?.trim().orEmpty()
    }

    private fun queryDirectoryName(
        treeUri: Uri,
        documentId: String,
    ): String {
        val documentUri = documentUri(treeUri, documentId)
        return contentResolver
            .query(documentUri, DIRECTORY_PROJECTION, null, null, null)
            ?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    return@use ""
                }
                val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                if (nameIndex >= 0) {
                    cursor.getString(nameIndex)?.trim().orEmpty()
                } else {
                    ""
                }
            }
            .orEmpty()
    }

    private fun documentUri(
        treeUri: Uri,
        documentId: String,
    ): Uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)

    private fun hasPersistedReadPermission(treeUri: Uri): Boolean {
        return contentResolver.persistedUriPermissions.any { permission ->
            permission.isReadPermission && permission.uri == treeUri
        }
    }

    private fun hasPersistedWritePermission(treeUri: Uri): Boolean {
        return contentResolver.persistedUriPermissions.any { permission ->
            permission.isWritePermission && permission.uri == treeUri
        }
    }

    private fun isImageDocument(
        displayName: String,
        mimeType: String,
    ): Boolean {
        if (mimeType.startsWith("image/")) {
            return true
        }
        val extension = displayName.substringAfterLast('.', "").lowercase()
        return extension in supportedImageExtensions
    }

    private val preferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private companion object {
        const val PREFS_NAME = "fly_player_screenshot_tree"
        const val KEY_TREE_URI = "tree_uri"
        const val KEY_TREE_NAME = "tree_name"
        val DIRECTORY_PROJECTION =
            arrayOf(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            )
        val CHILD_PROJECTION =
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
        val supportedImageExtensions =
            setOf("jpg", "jpeg", "png", "webp", "bmp")
    }
}
