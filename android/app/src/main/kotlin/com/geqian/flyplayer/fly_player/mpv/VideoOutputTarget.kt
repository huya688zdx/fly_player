package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.SurfaceTexture
import android.view.Surface
import android.view.TextureView
import android.view.View

interface VideoOutputTarget {
    val view: View
    val isSurfaceReady: Boolean

    fun currentSurface(): Surface?

    fun isSurfaceValid(): Boolean

    fun setListener(listener: Listener?)

    fun release()

    interface Listener {
        fun onSurfaceAvailable(
            surface: Surface,
            generation: Long,
            width: Int,
            height: Int,
        )

        fun onSurfaceSizeChanged(
            surface: Surface,
            generation: Long,
            width: Int,
            height: Int,
        )

        fun onSurfaceDestroyed(generation: Long)
    }
}

class TextureViewVideoOutputTarget(
    context: Context,
) : VideoOutputTarget,
    TextureView.SurfaceTextureListener {
    private val textureView = TextureView(context)
    private var listener: VideoOutputTarget.Listener? = null
    private var currentSurface: Surface? = null
    private var currentGeneration = 0L

    init {
        textureView.isOpaque = true
        textureView.surfaceTextureListener = this
    }

    override val view: View
        get() = textureView

    override val isSurfaceReady: Boolean
        get() = isSurfaceValid()

    override fun currentSurface(): Surface? = currentSurface

    override fun isSurfaceValid(): Boolean = currentSurface?.isValid == true

    override fun setListener(listener: VideoOutputTarget.Listener?) {
        this.listener = listener
    }

    override fun release() {
        listener = null
        textureView.surfaceTextureListener = null
        releaseCurrentSurface()
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
        releaseCurrentSurface()
        currentGeneration += 1L
        val nextSurface = Surface(surface)
        currentSurface = nextSurface
        listener?.onSurfaceAvailable(nextSurface, currentGeneration, width, height)
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
        val current = currentSurface ?: return
        listener?.onSurfaceSizeChanged(current, currentGeneration, width, height)
    }

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        val generation = currentGeneration
        listener?.onSurfaceDestroyed(generation)
        releaseCurrentSurface()
        return true
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit

    private fun releaseCurrentSurface() {
        currentSurface?.release()
        currentSurface = null
    }
}
