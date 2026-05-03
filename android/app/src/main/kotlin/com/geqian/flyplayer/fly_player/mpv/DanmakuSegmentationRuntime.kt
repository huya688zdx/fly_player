package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import com.baidu.paddle.fastdeploy.RuntimeOption
import com.baidu.paddle.fastdeploy.vision.DetectionResult
import com.baidu.paddle.fastdeploy.vision.SegmentationResult
import com.baidu.paddle.fastdeploy.vision.detection.PicoDet
import com.baidu.paddle.fastdeploy.vision.segmentation.PaddleSegModel
import java.io.File
import java.io.IOException
import kotlin.math.max
import kotlin.math.min

private const val DANMAKU_PADDLE_DEFAULT_INPUT_WIDTH = 256
private const val DANMAKU_PADDLE_DEFAULT_INPUT_HEIGHT = 144
private const val DANMAKU_PADDLE_DEFAULT_DETECTION_SIZE = 320
private const val DANMAKU_PADDLE_CACHE_DIR_NAME = "danmaku_ai_paddle_models"

private data class DanmakuPaddleSegmentationMetadata(
    val modelAssetDir: String,
    val inputWidth: Int,
    val inputHeight: Int,
    val outputWidth: Int,
    val outputHeight: Int,
)

private data class DanmakuPaddleDetectionMetadata(
    val modelAssetDir: String,
    val inputWidth: Int,
    val inputHeight: Int,
    val personLabelId: Int,
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

data class DanmakuDetectionCandidate(
    val score: Float,
    val rect: DanmakuNormalizedRect,
)

private data class DanmakuRuntimeTuning(
    val cpuThreadNum: Int,
    val litePowerMode: String,
)

data class DanmakuSegmentationOutput(
    val maskValues: FloatArray,
    val width: Int,
    val height: Int,
)

interface DanmakuSegmentationRuntime : AutoCloseable {
    val backend: DanmakuAiBackend
    val inputWidth: Int
    val inputHeight: Int
    val outputWidth: Int
    val outputHeight: Int

    fun run(bitmap: Bitmap): DanmakuSegmentationOutput
}

interface DanmakuDetectionRuntime : AutoCloseable {
    val backend: DanmakuAiBackend
    val inputWidth: Int
    val inputHeight: Int

    fun run(
        bitmap: Bitmap,
        scoreThreshold: Float,
    ): List<DanmakuDetectionCandidate>
}

private class PaddleSegmentationRuntime(
    private val predictor: PaddleSegModel,
    private val metadata: DanmakuPaddleSegmentationMetadata,
) : DanmakuSegmentationRuntime {
    override val backend: DanmakuAiBackend = DanmakuAiBackend.PADDLE
    override val inputWidth: Int = metadata.inputWidth
    override val inputHeight: Int = metadata.inputHeight
    override val outputWidth: Int = metadata.outputWidth
    override val outputHeight: Int = metadata.outputHeight

    private val result = SegmentationResult()

    override fun run(bitmap: Bitmap): DanmakuSegmentationOutput {
        check(predictor.initialized()) { "PaddleSegModel is not initialized" }
        check(predictor.predict(bitmap, result) && result.initialized()) {
            "PaddleSegModel prediction failed"
        }

        val dynamicShape = result.mShape?.takeIf { it.size >= 2 }
        val actualHeight = dynamicShape?.get(dynamicShape.size - 2)?.toInt()?.takeIf { it > 0 } ?: outputHeight
        val actualWidth = dynamicShape?.get(dynamicShape.size - 1)?.toInt()?.takeIf { it > 0 } ?: outputWidth
        val expectedPixels = actualWidth * actualHeight
        val scoreMap = result.mScoreMap
        if (result.mContainScoreMap && scoreMap != null) {
            when {
                scoreMap.size == expectedPixels -> {
                    return DanmakuSegmentationOutput(
                        maskValues = scoreMap.copyOf(),
                        width = actualWidth,
                        height = actualHeight,
                    )
                }
                scoreMap.size == expectedPixels * 2 -> {
                    return DanmakuSegmentationOutput(
                        maskValues = scoreMap.copyOfRange(expectedPixels, scoreMap.size),
                        width = actualWidth,
                        height = actualHeight,
                    )
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
        return DanmakuSegmentationOutput(
            maskValues = mask,
            width = actualWidth,
            height = actualHeight,
        )
    }

    override fun close() {
        runCatching { result.releaseCxxBuffer() }
        runCatching { predictor.release() }
    }
}

private class PaddleDetectionRuntime(
    private val predictor: PicoDet,
    private val metadata: DanmakuPaddleDetectionMetadata,
) : DanmakuDetectionRuntime {
    override val backend: DanmakuAiBackend = DanmakuAiBackend.PADDLE
    override val inputWidth: Int = metadata.inputWidth
    override val inputHeight: Int = metadata.inputHeight

    override fun run(
        bitmap: Bitmap,
        scoreThreshold: Float,
    ): List<DanmakuDetectionCandidate> {
        check(predictor.initialized()) { "PicoDet is not initialized" }
        val result = predictor.predict(bitmap, false, scoreThreshold)
        if (!result.initialized()) {
            return emptyList()
        }
        return parseDetectionResult(
            result = result,
            bitmapWidth = bitmap.width,
            bitmapHeight = bitmap.height,
            personLabelId = metadata.personLabelId,
        )
    }

    override fun close() {
        runCatching { predictor.release() }
    }

    private fun parseDetectionResult(
        result: DetectionResult,
        bitmapWidth: Int,
        bitmapHeight: Int,
        personLabelId: Int,
    ): List<DanmakuDetectionCandidate> {
        val boxes = result.mBoxes ?: return emptyList()
        val scores = result.mScores ?: return emptyList()
        val labelIds = result.mLabelIds ?: return emptyList()
        val count = min(boxes.size, min(scores.size, labelIds.size))
        if (count <= 0 || bitmapWidth <= 0 || bitmapHeight <= 0) {
            return emptyList()
        }
        val candidates = ArrayList<DanmakuDetectionCandidate>(count)
        for (index in 0 until count) {
            if (labelIds[index] != personLabelId) {
                continue
            }
            val score = scores[index]
            if (score <= 0f) {
                continue
            }
            val box = boxes[index]
            if (box == null || box.size < 4) {
                continue
            }
            val left = min(box[0], box[2]).coerceIn(0f, bitmapWidth.toFloat())
            val top = min(box[1], box[3]).coerceIn(0f, bitmapHeight.toFloat())
            val right = max(box[0], box[2]).coerceIn(0f, bitmapWidth.toFloat())
            val bottom = max(box[1], box[3]).coerceIn(0f, bitmapHeight.toFloat())
            val width = (right - left).coerceAtLeast(0f)
            val height = (bottom - top).coerceAtLeast(0f)
            if (width < 2f || height < 2f) {
                continue
            }
            candidates +=
                DanmakuDetectionCandidate(
                    score = score,
                    rect =
                        DanmakuNormalizedRect(
                            x = (left / bitmapWidth.toFloat()).coerceIn(0f, 1f),
                            y = (top / bitmapHeight.toFloat()).coerceIn(0f, 1f),
                            width = (width / bitmapWidth.toFloat()).coerceIn(0f, 1f),
                            height = (height / bitmapHeight.toFloat()).coerceIn(0f, 1f),
                        ),
                )
        }
        return candidates
    }
}

class DanmakuSegmentationRuntimeFactory(
    private val context: Context,
    private val paddleModelAssetDir: String,
) {
    private val deviceProfile: DanmakuDeviceProfile by lazy(::detectDeviceProfile)
    private val paddleMetadata: DanmakuPaddleSegmentationMetadata by lazy {
        readSegmentationModelMetadata(context, paddleModelAssetDir)
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
        metadata: DanmakuPaddleSegmentationMetadata,
    ): DanmakuSegmentationRuntime {
        val modelDir = materializeAssetDirectory(metadata.modelAssetDir)
        val modelFile = File(modelDir, "model.pdmodel")
        val paramsFile = File(modelDir, "model.pdiparams")
        val configFile = File(modelDir, "deploy.yaml")
        check(modelFile.isFile) { "Missing Paddle model file: ${modelFile.absolutePath}" }
        check(paramsFile.isFile) { "Missing Paddle params file: ${paramsFile.absolutePath}" }
        check(configFile.isFile) { "Missing Paddle deploy file: ${configFile.absolutePath}" }

        val option = createRuntimeOption(modelDir, resolveRuntimeTuning(deviceProfile))
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

    private fun readSegmentationModelMetadata(
        context: Context,
        assetDir: String,
    ): DanmakuPaddleSegmentationMetadata {
        val deployText =
            context.assets.open("$assetDir/deploy.yaml").bufferedReader().use { reader ->
                reader.readText()
            }
        val parsedSize = parseDeployTargetSize(deployText)
        return DanmakuPaddleSegmentationMetadata(
            modelAssetDir = assetDir,
            inputWidth = parsedSize.first,
            inputHeight = parsedSize.second,
            outputWidth = parsedSize.first,
            outputHeight = parsedSize.second,
        )
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

class DanmakuDetectionRuntimeFactory(
    private val context: Context,
    private val paddleModelAssetDir: String,
) {
    private val deviceProfile: DanmakuDeviceProfile by lazy(::detectDeviceProfile)
    private val paddleMetadata: DanmakuPaddleDetectionMetadata by lazy {
        readDetectionModelMetadata(context, paddleModelAssetDir)
    }

    fun create(backend: DanmakuAiBackend): DanmakuDetectionRuntime {
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
        metadata: DanmakuPaddleDetectionMetadata,
    ): DanmakuDetectionRuntime {
        val modelDir = materializeAssetDirectory(metadata.modelAssetDir)
        val modelFile = File(modelDir, "model.pdmodel")
        val paramsFile = File(modelDir, "model.pdiparams")
        val configFile = File(modelDir, "infer_cfg.yml")
        check(modelFile.isFile) { "Missing Paddle model file: ${modelFile.absolutePath}" }
        check(paramsFile.isFile) { "Missing Paddle params file: ${paramsFile.absolutePath}" }
        check(configFile.isFile) { "Missing Paddle infer file: ${configFile.absolutePath}" }

        val option = createRuntimeOption(modelDir, resolveRuntimeTuning(deviceProfile))
        val predictor = PicoDet()
        check(
            predictor.init(
                modelFile.absolutePath,
                paramsFile.absolutePath,
                configFile.absolutePath,
                option,
            ) && predictor.initialized(),
        ) {
            "FastDeploy PicoDet initialization failed"
        }
        return PaddleDetectionRuntime(
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

    private fun readDetectionModelMetadata(
        context: Context,
        assetDir: String,
    ): DanmakuPaddleDetectionMetadata {
        val inferCfgText =
            context.assets.open("$assetDir/infer_cfg.yml").bufferedReader().use { reader ->
                reader.readText()
            }
        val parsedSize = parseTargetSizeBlock(inferCfgText)
        val labels = parseListBlock(inferCfgText, "label_list")
        val personLabelId = labels.indexOfFirst { it.trim().lowercase() == "person" }.takeIf { it >= 0 } ?: 0
        return DanmakuPaddleDetectionMetadata(
            modelAssetDir = assetDir,
            inputWidth = parsedSize.first,
            inputHeight = parsedSize.second,
            personLabelId = personLabelId,
        )
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
                File(destinationRoot, "infer_cfg.yml"),
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

private fun resolveRuntimeTuning(deviceProfile: DanmakuDeviceProfile): DanmakuRuntimeTuning {
    val fingerprint =
        listOf(
            deviceProfile.socManufacturer,
            deviceProfile.hardware,
            deviceProfile.board,
            deviceProfile.manufacturer,
            deviceProfile.supportedAbis.joinToString(","),
        ).joinToString("|")
    val isMediaTek =
        fingerprint.contains("mediatek") ||
            fingerprint.contains("mt") ||
            fingerprint.contains("dimensity")
    return if (isMediaTek) {
        DanmakuRuntimeTuning(
            cpuThreadNum = 2,
            litePowerMode = "LITE_POWER_NO_BIND",
        )
    } else {
        DanmakuRuntimeTuning(
            cpuThreadNum = 3,
            litePowerMode = "LITE_POWER_HIGH",
        )
    }
}

private fun createRuntimeOption(
    modelDir: File,
    tuning: DanmakuRuntimeTuning,
): RuntimeOption {
    return RuntimeOption().apply {
        setCpuThreadNum(tuning.cpuThreadNum)
        setLitePowerMode(tuning.litePowerMode)
        enableLiteFp16()
        setLiteOptimizedModelDir(File(modelDir, "lite_opt").absolutePath)
    }
}

private fun parseDeployTargetSize(deployText: String): Pair<Int, Int> {
    return parseTargetSizeBlock(
        text = deployText,
        fallbackWidth = DANMAKU_PADDLE_DEFAULT_INPUT_WIDTH,
        fallbackHeight = DANMAKU_PADDLE_DEFAULT_INPUT_HEIGHT,
    )
}

private fun parseTargetSizeBlock(text: String): Pair<Int, Int> {
    return parseTargetSizeBlock(
        text = text,
        fallbackWidth = DANMAKU_PADDLE_DEFAULT_DETECTION_SIZE,
        fallbackHeight = DANMAKU_PADDLE_DEFAULT_DETECTION_SIZE,
    )
}

private fun parseTargetSizeBlock(
    text: String,
    fallbackWidth: Int,
    fallbackHeight: Int,
): Pair<Int, Int> {
    val values = mutableListOf<Int>()
    var collecting = false
    for (rawLine in text.lineSequence()) {
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
    return fallbackWidth to fallbackHeight
}

private fun parseListBlock(
    text: String,
    blockName: String,
): List<String> {
    val values = mutableListOf<String>()
    var collecting = false
    for (rawLine in text.lineSequence()) {
        val line = rawLine.trim()
        if (!collecting) {
            if (line == "$blockName:") {
                collecting = true
            }
            continue
        }
        val match = Regex("""^-\s*(.+?)\s*$""").find(line)
        if (match != null) {
            values += match.groupValues[1].trim()
            continue
        }
        if (line.isNotEmpty()) {
            break
        }
    }
    return values
}
