package com.geqian.flyplayer.fly_player

import android.content.ContentResolver
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import java.io.File
import kotlin.math.max

internal data class ScreenshotImageFormatInfo(
    val formatKind: String,
    val isHdr: Boolean,
)

internal object ScreenshotImageFormatInspector {
    fun inspectFile(file: File): ScreenshotImageFormatInfo {
        val baseFormat = baseFormatKind(displayName = file.name, mimeType = "")
        val isHdr =
            when {
                baseFormat != "jpeg" -> false
                Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> false
                else ->
                    runCatching {
                        val source = ImageDecoder.createSource(file)
                        decodeHasGainmap(source)
                    }.getOrDefault(false)
            }
        return ScreenshotImageFormatInfo(
            formatKind = if (isHdr) "ultra_hdr_jpeg" else baseFormat,
            isHdr = isHdr,
        )
    }

    fun inspectUri(
        contentResolver: ContentResolver,
        uri: Uri,
        displayName: String,
        mimeType: String,
    ): ScreenshotImageFormatInfo {
        val baseFormat = baseFormatKind(displayName = displayName, mimeType = mimeType)
        val isHdr =
            when {
                baseFormat != "jpeg" -> false
                Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> false
                else ->
                    runCatching {
                        val source = ImageDecoder.createSource(contentResolver, uri)
                        decodeHasGainmap(source)
                    }.getOrDefault(false)
            }
        return ScreenshotImageFormatInfo(
            formatKind = if (isHdr) "ultra_hdr_jpeg" else baseFormat,
            isHdr = isHdr,
        )
    }

    private fun decodeHasGainmap(source: ImageDecoder.Source): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return false
        }
        val bitmap =
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE)
                val maxDimension = max(info.size.width, info.size.height)
                val sampleSize = (maxDimension / 1024).coerceAtLeast(1)
                decoder.setTargetSampleSize(sampleSize)
            }
        return try {
            bitmap.hasGainmap()
        } finally {
            bitmap.recycle()
        }
    }

    private fun baseFormatKind(
        displayName: String,
        mimeType: String,
    ): String {
        val normalizedMime = mimeType.trim().lowercase()
        if (normalizedMime == "image/png") return "png"
        if (normalizedMime == "image/webp") return "webp"
        if (normalizedMime == "image/bmp") return "bmp"
        if (normalizedMime == "image/jpeg" || normalizedMime == "image/jpg") {
            return "jpeg"
        }
        return when (displayName.substringAfterLast('.', "").lowercase()) {
            "jpg", "jpeg", "jpegr" -> "jpeg"
            "png" -> "png"
            "webp" -> "webp"
            "bmp" -> "bmp"
            else -> "image"
        }
    }
}
