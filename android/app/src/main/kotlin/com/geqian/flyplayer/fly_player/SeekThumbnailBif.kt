package com.geqian.flyplayer.fly_player

import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Roku BIF（Base Index Frames）解析：Emby「视频预览缩略图提取」任务按 MediaSource 生成的
 * 单文件——整片按固定间隔抽帧的 JPEG 序列 + 时间索引，密度远高于章节图。
 *
 * 文件布局（数值均为小端 uint32）：
 * - 0..7   魔数 `89 42 49 46 0D 0A 1A 0A`
 * - 8      版本
 * - 12     帧数 N
 * - 16     时间戳乘数（毫秒/单位，0 视为 1000）
 * - 20..63 保留
 * - 64     索引：N+1 条 {timestamp, absoluteOffset}，末条为终止哨兵（offset = 数据末尾）
 * - 之后    JPEG 帧数据，第 i 帧字节区间 = [offset[i], offset[i+1])
 *
 * 纯字节解析、无 Android 依赖（可 JVM 单测）。
 */
object BifThumbnails {

    /** 解析结果：帧时间戳（ms，升序）+ 完整文件字节（帧按偏移切片取用）。 */
    class Index(
        private val data: ByteArray,
        val timestampsMs: LongArray,
        private val offsets: LongArray,
    ) {
        val frameCount: Int get() = timestampsMs.size

        /** 取「起始时间 <= 目标」的最后一帧下标；都在目标之后取第 0 帧。 */
        fun frameIndexFor(positionMs: Long): Int {
            var lo = 0
            var hi = timestampsMs.size - 1
            var ans = 0
            while (lo <= hi) {
                val mid = (lo + hi) ushr 1
                if (timestampsMs[mid] <= positionMs) {
                    ans = mid
                    lo = mid + 1
                } else {
                    hi = mid - 1
                }
            }
            return ans
        }

        /** 第 [index] 帧的 JPEG 字节（拷贝切片，几 KB 级）。 */
        fun frameBytes(index: Int): ByteArray =
            data.copyOfRange(offsets[index].toInt(), offsets[index + 1].toInt())
    }

    private val MAGIC =
        byteArrayOf(0x89.toByte(), 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A)
    private const val HEADER_SIZE = 64

    // 帧数上限兜底：320 宽 @2s 间隔的 24h 内容也不过 4.3 万帧，超出视为脏数据。
    private const val MAX_FRAMES = 200_000

    /** 解析整个 BIF 文件字节；魔数/索引非法、偏移越界或乱序返回 null（调用方退回章节图）。 */
    fun parse(data: ByteArray): Index? {
        if (data.size < HEADER_SIZE + 16) return null
        for (i in MAGIC.indices) if (data[i] != MAGIC[i]) return null
        val count = readUInt32(data, 12)
        if (count <= 0L || count > MAX_FRAMES) return null
        val multiplier = readUInt32(data, 16).let { if (it == 0L) 1000L else it }
        val entries = count.toInt() + 1
        val indexEnd = HEADER_SIZE + entries * 8L
        if (indexEnd > data.size) return null
        val timestamps = LongArray(count.toInt())
        val offsets = LongArray(entries)
        var prevTimestamp = -1L
        var prevOffset = indexEnd
        for (i in 0 until entries) {
            val base = HEADER_SIZE + i * 8
            val offset = readUInt32(data, base + 4)
            if (offset < prevOffset || offset > data.size) return null
            offsets[i] = offset
            prevOffset = offset
            if (i < count.toInt()) {
                val ts = readUInt32(data, base) * multiplier
                if (ts < prevTimestamp) return null
                timestamps[i] = ts
                prevTimestamp = ts
            }
        }
        return Index(data, timestamps, offsets)
    }

    private fun readUInt32(data: ByteArray, at: Int): Long =
        (data[at].toLong() and 0xFF) or
            ((data[at + 1].toLong() and 0xFF) shl 8) or
            ((data[at + 2].toLong() and 0xFF) shl 16) or
            ((data[at + 3].toLong() and 0xFF) shl 24)
}

/**
 * BIF 下载与就绪态管理（原生壳 seek 预览用）。
 *
 * [prepare] 后台下载到磁盘缓存（按 URL 哈希命名，跨会话复用）并解析进内存；就绪前
 * [frameFor] 返回 null，调用方退回章节图/纯时间药丸。换源换 URL 时旧数据即时作废
 * （generation 竞态门），同 URL 重载（切音轨/画质等）直接复用已就绪数据。
 * 服务端未生成 BIF（404）静默失败，不重试（本次播放内保持章节图兜底）。
 */
class SeekThumbnailBifStore(private val cacheDir: File) {

    class Frame(val index: Int, val bytes: ByteArray)

    private val lock = Any()
    private var currentUrl = ""
    private var loading = false
    private var generation = 0

    @Volatile
    private var index: BifThumbnails.Index? = null

    private val http by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    /** 装载入口（onCreate / 换源均走这里）：空 URL 清空；同 URL 已就绪/在途则复用。 */
    fun prepare(url: String, headers: Map<String, String>) {
        val myGeneration: Int
        synchronized(lock) {
            if (url == currentUrl && (index != null || loading || url.isEmpty())) return
            currentUrl = url
            index = null
            generation++
            if (url.isEmpty()) {
                loading = false
                return
            }
            loading = true
            myGeneration = generation
        }
        Thread {
            val parsed = try {
                loadOrDownload(url, headers)
            } catch (e: Throwable) {
                Log.w(TAG, "bif load failed: ${e.message}")
                null
            }
            synchronized(lock) {
                if (generation == myGeneration) {
                    index = parsed
                    loading = false
                }
            }
        }.apply {
            name = "bif-seek-thumbs"
            isDaemon = true
        }.start()
    }

    /** 取最接近 [positionMs] 的帧；BIF 未就绪/无 BIF 返回 null。纯内存切片，可在主线程调。 */
    fun frameFor(positionMs: Long): Frame? {
        val idx = index ?: return null
        val i = idx.frameIndexFor(positionMs)
        return Frame(i, idx.frameBytes(i))
    }

    /** 磁盘缓存命中直接解析；未命中则下载（带播放 headers 过 fnos 中转闸）后落盘再解析。 */
    private fun loadOrDownload(
        url: String,
        headers: Map<String, String>,
    ): BifThumbnails.Index? {
        cacheDir.mkdirs()
        val cacheFile = File(cacheDir, "${sha1(url)}.bif")
        if (cacheFile.isFile) {
            val cached = BifThumbnails.parse(cacheFile.readBytes())
            if (cached != null) {
                cacheFile.setLastModified(System.currentTimeMillis())
                return cached
            }
            cacheFile.delete() // 脏缓存（半截下载/格式变化）重下
        }
        val request = Request.Builder().url(url).apply {
            for ((name, value) in headers) {
                if (name.isNotEmpty() && value.isNotEmpty()) addHeader(name, value)
            }
        }.build()
        val bytes = http.newCall(request).execute().use { response ->
            // 404 = 服务端未跑「视频预览缩略图提取」任务，属常态，静默退回章节图。
            if (!response.isSuccessful) return null
            val body = response.body ?: return null
            if (body.contentLength() > MAX_BIF_BYTES) return null
            readCapped(body.byteStream(), MAX_BIF_BYTES) ?: return null
        }
        val parsed = BifThumbnails.parse(bytes) ?: return null
        // 先写临时文件再改名，避免半截文件被后续会话当有效缓存。
        val tmp = File(cacheDir, "${cacheFile.name}.tmp")
        try {
            tmp.writeBytes(bytes)
            if (!tmp.renameTo(cacheFile)) tmp.delete()
        } catch (e: Throwable) {
            tmp.delete()
        }
        evictOld(keep = cacheFile.name)
        return parsed
    }

    /** 限量读取；超过 [cap] 视为异常数据放弃（防脏服务端把内存拖爆）。 */
    private fun readCapped(input: java.io.InputStream, cap: Long): ByteArray? {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            total += read
            if (total > cap) return null
            out.write(buffer, 0, read)
        }
        return out.toByteArray()
    }

    /** 缓存目录只留最近 [MAX_CACHE_FILES] 个 BIF（LRU by lastModified），当前文件豁免。 */
    private fun evictOld(keep: String) {
        val files = cacheDir.listFiles { f -> f.isFile && f.name.endsWith(".bif") } ?: return
        if (files.size <= MAX_CACHE_FILES) return
        files.sortedBy { it.lastModified() }
            .filter { it.name != keep }
            .take(files.size - MAX_CACHE_FILES)
            .forEach { it.delete() }
    }

    private fun sha1(text: String): String =
        MessageDigest.getInstance("SHA-1")
            .digest(text.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    companion object {
        private const val TAG = "SeekThumbnailBif"
        private const val MAX_BIF_BYTES = 128L * 1024 * 1024
        private const val MAX_CACHE_FILES = 16
    }
}
