package com.geqian.flyplayer.fly_player.mpv

/**
 * JNI binding to libmnnseg.so (MNN Interpreter wrapper).
 *
 * Backends (wire value): 0 = CPU, 3 = OpenCL, 7 = Vulkan. Use Vulkan by default
 * — it is the only backend stable on both Adreno and Mali (see
 * docs/danmaku-occlusion-rework-plan.md Phase 0 benchmark).
 *
 * One handle can run the (fully-convolutional) model at multiple input sizes;
 * [nativeRun] takes the desired square size N.
 */
internal object MnnSegNative {
    @Volatile
    private var available: Boolean = false

    init {
        available =
            runCatching {
                // Preload the MNN core explicitly so libmnnseg's NEEDED dependency
                // resolves regardless of linker search order. The GPU backends
                // (libMNN_Vulkan / libMNN_CL) are dlopen-ed by libMNN at runtime
                // from the same nativeLibraryDir, so they don't need preloading here.
                runCatching { System.loadLibrary("MNN") }
                System.loadLibrary("mnnseg")
            }.isSuccess
    }

    val isAvailable: Boolean
        get() = available

    const val BACKEND_CPU = 0
    const val BACKEND_OPENCL = 3
    const val BACKEND_VULKAN = 7

    /** Returns a native handle (0 on failure). */
    external fun nativeCreate(
        modelPath: String,
        backend: Int,
        threads: Int,
    ): Long

    /**
     * Runs inference. [input] is a normalized NCHW float buffer of length 3*n*n.
     * Returns the mask as float[n*n] (raw model output; caller normalizes), or
     * null on failure.
     */
    external fun nativeRun(
        handle: Long,
        input: FloatArray,
        n: Int,
    ): FloatArray?

    external fun nativeDestroy(handle: Long)
}
