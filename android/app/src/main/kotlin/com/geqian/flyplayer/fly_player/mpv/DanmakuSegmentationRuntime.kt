package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import com.baidu.paddle.fastdeploy.RuntimeOption
import com.baidu.paddle.fastdeploy.vision.SegmentationResult
import com.baidu.paddle.fastdeploy.vision.segmentation.PaddleSegModel
import java.io.File
import java.io.IOException

private const val DANMAKU_PADDLE_DEFAULT_INPUT_WIDTH = 256
private const val DANMAKU_PADDLE_DEFAULT_INPUT_HEIGHT = 144
private const val DANMAKU_PADDLE_CACHE_DIR_NAME = "danmaku_ai_paddle_models"

private data class DanmakuPaddleModelMetadata(
    val modelAssetDir: String,
    val inputWidth: Int,
    val inputHeight: Int,
    val outputWidth: Int,
    val outputHeight: Int,
)

private data class DanmakuDeviceProfile(
    val socManufacturer: String,
    val hardware: String,
    val board: String,
    val manufacturer: String,
    val supportedAbis: List<String>,
) {
    val summary: String
        get() =
            "socManufacturer=$socManufacturer hardware=$hardware board=$board " +
                "manufacturer=$manufacturer supportedAbis=${supportedAbis.joinToString(",")}"
}

interface DanmakuSegmentationRuntime : AutoCloseable {
    val backend: DanmakuAiBackend
    val inputWidth: Int
    val inputHeight: Int
    val outputWidth: Int
    val outputHeight: Int

    fun run(bitmap: Bitmap): FloatArray
}

private class PaddleSegmentationRuntime(
    private val predictor: PaddleSegModel,
    private val metadata: DanmakuPaddleModelMetadata,
) : DanmakuSegmentationRuntime {
    override val backend: DanmakuAiBackend = DanmakuAiBackend.PADDLE
    override val inputWidth: Int = metadata.inputWidth
    override val inputHeight: Int = metadata.inputHeight
    override val outputWidth: Int = metadata.outputWidth
    override val outputHeight: Int = metadata.outputHeight

    private val result = SegmentationResult()

    override fun run(bitmap: Bitmap): FloatArray {
        check(predictor.initialized()) { "PaddleSegModel is not initialized" }
        check(predictor.predict(bitmap, result) && result.initialized()) {
            "PaddleSegModel prediction failed"
        }

        val expectedPixels = outputWidth * outputHeight
        val scoreMap = result.mScoreMap
        if (result.mContainScoreMap && scoreMap != null) {
            when {
                scoreMap.size == expectedPixels -> {
                    return scoreMap.copyOf()
                }
                scoreMap.size == expectedPixels * 2 -> {
                    // Prefer the foreground/person-class plane.
                    return scoreMap.copyOfRange(expectedPixels, scoreMap.size)
                }
            }
        }

        val labelMap = result.mLabelMap ?: error("PaddleSegModel returned no label map")
        check(labelMap.size == expectedPixels) {
            "Unexpected PaddleSeg label size=${labelMap.size} expected=$expectedPixels shape=${result.mShape?.joinToString()}"
        }
        val mask = FloatArray(expectedPixels)
        for (index in 0 until expectedPixels) {
            mask[index] = if ((labelMap[index].toInt() and 0xFF) > 0) 1f else 0f
        }
        return mask
    }

    override fun close() {
        runCatching { result.releaseCxxBuffer() }
        runCatching { predictor.release() }
    }
}

class DanmakuSegmentationRuntimeFactory(
    private val context: Context,
    private val paddleModelAssetDir: String,
) {
    private val deviceProfile: DanmakuDeviceProfile by lazy(::detectDeviceProfile)
    private val paddleMetadata: DanmakuPaddleModelMetadata by lazy {
        readPaddleModelMetadata(context, paddleModelAssetDir)
    }

    fun create(
        backend: DanmakuAiBackend,
        config: DanmakuDynamicOcclusionConfig,
    ): DanmakuSegmentationRuntime {
        check(config.preferredBackendOrder.contains(DanmakuAiBackend.PADDLE)) {
            "Paddle backend must remain enabled"
        }
        return when (backend) {
            DanmakuAiBackend.PADDLE -> createPaddleRuntime(paddleMetadata)
            DanmakuAiBackend.GPU,
            DanmakuAiBackend.CPU,
            -> error("backend ${backend.wireValue} is no longer supported")
            DanmakuAiBackend.DISABLED -> error("disabled backend cannot create runtime")
        }
    }

    fun shouldAttempt(backend: DanmakuAiBackend): Boolean {
        return when (backend) {
            DanmakuAiBackend.PADDLE -> assetDirectoryExists(paddleModelAssetDir)
            DanmakuAiBackend.GPU,
            DanmakuAiBackend.CPU,
            DanmakuAiBackend.DISABLED,
            -> false
        }
    }

    fun deviceSummary(): String = deviceProfile.summary

    private fun createPaddleRuntime(
        metadata: DanmakuPaddleModelMetadata,
    ): DanmakuSegmentationRuntime {
        val modelDir = materializeAssetDirectory(metadata.modelAssetDir)
        val modelFile = File(modelDir, "model.pdmodel")
        val paramsFile = File(modelDir, "model.pdiparams")
        val configFile = File(modelDir, "deploy.yaml")
        check(modelFile.isFile) { "Missing Paddle model file: ${modelFile.absolutePath}" }
        check(paramsFile.isFile) { "Missing Paddle params file: ${paramsFile.absolutePath}" }
        check(configFile.isFile) { "Missing Paddle deploy file: ${configFile.absolutePath}" }

        val option =
            RuntimeOption().apply {
                setCpuThreadNum(Runtime.getRuntime().availableProcessors().coerceIn(1, 4))
                setLitePowerMode("LITE_POWER_HIGH")
                enableLiteFp16()
                setLiteOptimizedModelDir(File(modelDir, "lite_opt").absolutePath)
            }
        val predictor = PaddleSegModel()
        predictor.setVerticalScreenFlag(metadata.inputHeight > metadata.inputWidth)
        check(
            predictor.init(
                modelFile.absolutePath,
                paramsFile.absolutePath,
                configFile.absolutePath,
                option,
            ) && predictor.initialized(),
        ) {
            "FastDeploy PaddleSegModel initialization failed"
        }
        return PaddleSegmentationRuntime(
            predictor = predictor,
            metadata = metadata,
        )
    }

    private fun detectDeviceProfile(): DanmakuDeviceProfile {
        fun normalize(value: String?): String {
            return value?.trim()?.lowercase().orEmpty()
        }

        val socManufacturer =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                normalize(Build.SOC_MANUFACTURER)
            } else {
                ""
            }
        return DanmakuDeviceProfile(
            socManufacturer = socManufacturer,
            hardware = normalize(Build.HARDWARE),
            board = normalize(Build.BOARD),
            manufacturer = normalize(Build.MANUFACTURER),
            supportedAbis = Build.SUPPORTED_ABIS.map(::normalize),
        )
    }

    private fun readPaddleModelMetadata(
        context: Context,
        assetDir: String,
    ): DanmakuPaddleModelMetadata {
        val deployText =
            context.assets.open("$assetDir/deploy.yaml").bufferedReader().use { reader ->
                reader.readText()
            }
        val parsedSize = parseDeployTargetSize(deployText)
        return DanmakuPaddleModelMetadata(
            modelAssetDir = assetDir,
            inputWidth = parsedSize.first,
            inputHeight = parsedSize.second,
            outputWidth = parsedSize.first,
            outputHeight = parsedSize.second,
        )
    }

    private fun parseDeployTargetSize(
        deployText: String,
    ): Pair<Int, Int> {
        val values = mutableListOf<Int>()
        var collecting = false
        for (rawLine in deployText.lineSequence()) {
            val line = rawLine.trim()
            if (!collecting) {
                if (line == "target_size:") {
                    collecting = true
                }
                continue
            }
            val match = Regex("""^-\s*(\d+)\s*$""").find(line)
            if (match != null) {
                values += match.groupValues[1].toInt()
                if (values.size >= 2) {
                    break
                }
                continue
            }
            if (line.isNotEmpty()) {
                break
            }
        }
        if (values.size >= 2) {
            return values[0] to values[1]
        }
        return DANMAKU_PADDLE_DEFAULT_INPUT_WIDTH to DANMAKU_PADDLE_DEFAULT_INPUT_HEIGHT
    }

    private fun assetDirectoryExists(assetDir: String): Boolean {
        return runCatching {
            context.assets.list(assetDir)?.isNotEmpty() == true
        }.getOrDefault(false)
    }

    private fun materializeAssetDirectory(assetDir: String): File {
        val destinationRoot =
            File(File(context.cacheDir, DANMAKU_PADDLE_CACHE_DIR_NAME), assetDir.substringAfterLast('/'))
        val requiredFiles =
            listOf(
                File(destinationRoot, "model.pdmodel"),
                File(destinationRoot, "model.pdiparams"),
                File(destinationRoot, "deploy.yaml"),
            )
        if (requiredFiles.all(File::isFile)) {
            return destinationRoot
        }
        copyAssetDirectoryRecursively(assetDir, destinationRoot)
        return destinationRoot
    }

    private fun copyAssetDirectoryRecursively(
        assetPath: String,
        destination: File,
    ) {
        val entries = context.assets.list(assetPath).orEmpty()
        if (entries.isEmpty()) {
            destination.parentFile?.mkdirs()
            context.assets.open(assetPath).use { input ->
                destination.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            return
        }
        if (!destination.exists() && !destination.mkdirs()) {
            throw IOException("Failed to create directory ${destination.absolutePath}")
        }
        for (entry in entries) {
            val childAssetPath =
                if (assetPath.isEmpty()) {
                    entry
                } else {
                    "$assetPath/$entry"
                }
            copyAssetDirectoryRecursively(childAssetPath, File(destination, entry))
        }
    }
}
