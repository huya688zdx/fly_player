package com.geqian.flyplayer.fly_player

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract

class ScopedTreeAccessController(
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

    fun grantedRoot(): Map<String, Any?>? {
        val treeUri = currentTreeUri() ?: return null
        if (!hasPersistedReadPermission(treeUri)) {
            clearGrantedTree()
            return null
        }
        val rootId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull()
        if (rootId.isNullOrBlank()) {
            clearGrantedTree()
            return null
        }
        return buildDirectoryMap(treeUri = treeUri, documentId = rootId)
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
        preferences.edit().putString(KEY_TREE_URI, treeUri.toString()).apply()
        return grantedRoot()
    }

    fun listEntries(
        directoryId: String?,
        allowedExtensions: List<String>,
    ): Map<String, Any?>? {
        val treeUri = currentTreeUri() ?: return null
        if (!hasPersistedReadPermission(treeUri)) {
            clearGrantedTree()
            return null
        }
        val rootId = runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull()
        val targetId = directoryId?.trim().takeUnless { it.isNullOrEmpty() } ?: rootId
        if (targetId.isNullOrBlank()) {
            return null
        }
        val directory = buildDirectoryMap(treeUri = treeUri, documentId = targetId) ?: return null
        val allowed =
            allowedExtensions
                .map { it.trim().lowercase() }
                .filter { it.isNotEmpty() }
                .toSet()
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, targetId)
        val entries = mutableListOf<Map<String, Any?>>()
        contentResolver
            .query(
                childrenUri,
                CHILD_PROJECTION,
                null,
                null,
                null,
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeTypeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                val sizeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                while (cursor.moveToNext()) {
                    if (idIndex < 0 || nameIndex < 0 || mimeTypeIndex < 0) {
                        continue
                    }
                    val documentId = cursor.getString(idIndex)?.trim().orEmpty()
                    val displayName = cursor.getString(nameIndex)?.trim().orEmpty()
                    val mimeType = cursor.getString(mimeTypeIndex)?.trim().orEmpty()
                    if (documentId.isEmpty() || displayName.isEmpty() || displayName.startsWith(".")) {
                        continue
                    }
                    val isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                    if (!isDirectory) {
                        val extension = displayName.substringAfterLast('.', "").lowercase()
                        if (extension.isEmpty() || extension !in allowed) {
                            continue
                        }
                    }
                    val sizeBytes =
                        if (isDirectory || sizeIndex < 0 || cursor.isNull(sizeIndex)) {
                            0L
                        } else {
                            cursor.getLong(sizeIndex)
                        }
                    entries +=
                        mapOf(
                            "id" to documentId,
                            "name" to displayName,
                            "isDirectory" to isDirectory,
                            "sizeBytes" to sizeBytes,
                        )
                }
            }
        entries.sortWith(
            compareBy<Map<String, Any?>>(
                { it["isDirectory"] != true },
                { (it["name"] as? String).orEmpty().lowercase() },
            ),
        )
        return mapOf("directory" to directory, "entries" to entries)
    }

    fun readFileBytes(identifier: String): ByteArray? {
        val treeUri = currentTreeUri() ?: return null
        if (!hasPersistedReadPermission(treeUri)) {
            clearGrantedTree()
            return null
        }
        val documentId = identifier.trim()
        if (documentId.isEmpty()) {
            return null
        }
        val documentUri =
            DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        return contentResolver.openInputStream(documentUri)?.use { stream ->
            stream.readBytes()
        }
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
        clearGrantedTree()
    }

    private fun buildDirectoryMap(
        treeUri: Uri,
        documentId: String,
    ): Map<String, Any?>? {
        val documentUri =
            DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        val documentInfo = queryDocumentInfo(documentUri) ?: return null
        if (documentInfo.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) {
            return null
        }
        val displayName =
            documentInfo.name.ifBlank {
                if (documentId == DocumentsContract.getTreeDocumentId(treeUri)) {
                    context.localizedString(R.string.storage_authorized_folder)
                } else {
                    context.localizedString(R.string.storage_folder)
                }
            }
        return mapOf("id" to documentId, "name" to displayName)
    }

    private fun queryDocumentInfo(documentUri: Uri): DocumentInfo? {
        return contentResolver
            .query(
                documentUri,
                DOCUMENT_PROJECTION,
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) {
                    return null
                }
                val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeTypeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                DocumentInfo(
                    name = if (nameIndex >= 0) cursor.getString(nameIndex).orEmpty() else "",
                    mimeType =
                        if (mimeTypeIndex >= 0) {
                            cursor.getString(mimeTypeIndex).orEmpty()
                        } else {
                            ""
                        },
                )
            }
    }

    private fun hasPersistedReadPermission(treeUri: Uri): Boolean {
        return contentResolver.persistedUriPermissions.any { permission ->
            permission.isReadPermission && permission.uri == treeUri
        }
    }

    private fun clearGrantedTree() {
        preferences.edit().remove(KEY_TREE_URI).apply()
    }

    private val preferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private data class DocumentInfo(
        val name: String,
        val mimeType: String,
    )

    private companion object {
        const val PREFS_NAME = "fly_player_scoped_tree"
        const val KEY_TREE_URI = "tree_uri"
        val DOCUMENT_PROJECTION =
            arrayOf(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            )
        val CHILD_PROJECTION =
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE,
            )
    }
}
