package com.geqian.flyplayer.fly_player

import android.content.Context
import com.bumptech.glide.Glide
import com.bumptech.glide.Priority
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.load.Options
import com.bumptech.glide.load.data.DataFetcher
import com.bumptech.glide.load.model.ModelLoader
import com.bumptech.glide.load.model.ModelLoaderFactory
import com.bumptech.glide.load.model.MultiModelLoaderFactory
import com.bumptech.glide.signature.ObjectKey
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream

class NativeSafeImageRequest(
    val url: String,
    headers: Map<String, String>,
) {
    val headers: Map<String, String> = NativeImageRequestHeaders.fromAny(headers)
    val cacheIdentity: String = NativeImageRequestHeaders.cacheIdentity(url, this.headers)
}

/** 让带敏感头的 Glide 图片也使用同源手动重定向策略。 */
object NativeSafeImageGlide {
    @Volatile
    private var registered = false

    fun model(
        context: Context,
        url: String,
        headers: Map<String, String>,
    ): Any {
        val safeHeaders = NativeImageRequestHeaders.fromAny(headers)
        if (safeHeaders.isEmpty()) return url
        ensureRegistered(context.applicationContext)
        return NativeSafeImageRequest(url, safeHeaders)
    }

    private fun ensureRegistered(context: Context) {
        if (registered) return
        synchronized(this) {
            if (registered) return
            Glide.get(context).registry.prepend(
                NativeSafeImageRequest::class.java,
                InputStream::class.java,
                NativeSafeImageModelLoader.Factory(),
            )
            registered = true
        }
    }
}

private class NativeSafeImageModelLoader : ModelLoader<NativeSafeImageRequest, InputStream> {
    override fun handles(model: NativeSafeImageRequest): Boolean = true

    override fun buildLoadData(
        model: NativeSafeImageRequest,
        width: Int,
        height: Int,
        options: Options,
    ): ModelLoader.LoadData<InputStream> =
        ModelLoader.LoadData(
            ObjectKey(model.cacheIdentity),
            NativeSafeImageDataFetcher(model),
        )

    class Factory : ModelLoaderFactory<NativeSafeImageRequest, InputStream> {
        override fun build(multiFactory: MultiModelLoaderFactory): ModelLoader<NativeSafeImageRequest, InputStream> =
            NativeSafeImageModelLoader()

        override fun teardown() = Unit
    }
}

private class NativeSafeImageDataFetcher(
    private val request: NativeSafeImageRequest,
) : DataFetcher<InputStream> {
    private val session = NativeSafeImageHttp.newSession(request.url, request.headers)

    @Volatile
    private var cancelled = false
    private var stream: InputStream? = null

    override fun loadData(
        priority: Priority,
        callback: DataFetcher.DataCallback<in InputStream>,
    ) {
        try {
            val bytes = session.fetchBytes()
            if (cancelled) return
            if (bytes == null) {
                callback.onLoadFailed(IOException("原生图片请求失败"))
                return
            }
            ByteArrayInputStream(bytes).also {
                stream = it
                callback.onDataReady(it)
            }
        } catch (error: Exception) {
            if (!cancelled) callback.onLoadFailed(error)
        }
    }

    override fun cleanup() {
        stream?.close()
        stream = null
    }

    override fun cancel() {
        cancelled = true
        session.cancel()
    }

    override fun getDataClass(): Class<InputStream> = InputStream::class.java

    override fun getDataSource(): DataSource = DataSource.REMOTE
}
