# 双 Flavor 打包方案：full（带 Paddle）/ lite（不带 Paddle）

> 目标：产出两个包。`full` 保留弹幕动态遮挡（Paddle 人体分割/检测，约 76MB 原生库 + 13MB 模型）；
> `lite` 去掉 Paddle，体积约从 ~222MB 降到 ~145MB，弹幕动态遮挡功能自动降级为「不可用」。

---

## 0. 为什么这个方案是干净的（关键事实）

调查结论（已逐一核实）：

1. **所有 `com.baidu.paddle.fastdeploy.*` 的 import 只集中在一个文件**：
   `android/app/src/main/kotlin/.../mpv/DanmakuSegmentationRuntime.kt`
   用到的 Paddle 符号仅 5 个：`RuntimeOption`、`vision.DetectionResult`、
   `vision.SegmentationResult`、`vision.detection.PicoDet`、`vision.segmentation.PaddleSegModel`。

2. **7800 行的 `DanmakuDynamicOcclusion.kt` 不直接 import 任何 paddle 类**，
   只通过 `DanmakuSegmentationRuntimeFactory` / `DanmakuDetectionRuntimeFactory`
   两个工厂类和 `DanmakuSegmentationRuntime` / `DanmakuDetectionRuntime` 接口间接调用。

3. Paddle 依赖来自 `android/app/libs/fastdeploy-android-sdk-latest-dev.aar`（48MB），
   在 `build.gradle.kts` 的 `dependencies { implementation(files(...)) }` 引入。
   它最终展开成 APK 里的 `libcore_tokenizers.so`(33M)、`libopencv_java4.so`(18M)、
   `libpaddle_full_api_shared.so`(15M)、`libfastdeploy*.so`、`libflycv_shared.so` 等。

4. 模型资源在 `android/app/src/main/assets/models/`（13MB，两个子目录
   `picodet_s_320_coco_lcnet`、`pp_humansegv2_lite`），不在 pubspec。

**因此隔离接缝 = `DanmakuSegmentationRuntime.kt` 这一个文件 + 它需要的工厂入口。**
`DanmakuDynamicOcclusion.kt` 完全不动。

---

## 1. 方案总览（flavor + sourceSet 隔离，不写一堆 stub）

用 Gradle **product flavors** + **per-flavor sourceSet** 实现：

- `full` flavor：
  - 引入 fastdeploy.aar
  - 用现有的 `DanmakuSegmentationRuntime.kt`（真实 Paddle 实现）
  - 打包 `assets/models/`
- `lite` flavor：
  - 不引入 fastdeploy.aar
  - 用一份**精简替身** `DanmakuSegmentationRuntime.kt`：保留**完全相同的公共 API**
    （工厂类、接口、数据类签名都不变），但 `shouldAttempt() 永远返回 false`、
    `create() 抛异常`。这样 `DanmakuDynamicOcclusion.kt` 不用改一行，
    运行时它调用 `shouldAttempt()` 得到 false → 自动跳过 AI 遮挡，功能降级。
  - 不打包 `assets/models/`

关键：把 `DanmakuSegmentationRuntime.kt` 从 `src/main` 移到 `src/full` 和 `src/lite`
各一份。`main` 里不再有这个文件，两个 flavor 各自提供。

---

## 2. 具体改动清单

### 改动 A：移动并拆分 `DanmakuSegmentationRuntime.kt`

1. 新建目录：
   ```
   android/app/src/full/kotlin/com/geqian/flyplayer/fly_player/mpv/
   android/app/src/lite/kotlin/com/geqian/flyplayer/fly_player/mpv/
   ```

2. 把现有
   `android/app/src/main/kotlin/com/geqian/flyplayer/fly_player/mpv/DanmakuSegmentationRuntime.kt`
   **移动**到
   `android/app/src/full/kotlin/com/geqian/flyplayer/fly_player/mpv/DanmakuSegmentationRuntime.kt`
   （内容不变，它就是真实 Paddle 实现）。

3. 在 `src/lite/.../mpv/DanmakuSegmentationRuntime.kt` 新建替身（见第 4 节完整代码）。
   它必须导出与 full 版**完全相同的对外符号**：
   - 接口 `DanmakuSegmentationRuntime`、`DanmakuDetectionRuntime`
   - 数据类 `DanmakuSegmentationOutput`、`DanmakuDetectionCandidate`
   - 工厂类 `DanmakuSegmentationRuntimeFactory`、`DanmakuDetectionRuntimeFactory`
     （构造签名一致：`(context: Context, paddleModelAssetDir: String)`，
     方法 `create(...)`、`shouldAttempt(...)`、`deviceSummary()` 一致）

   > ⚠️ 务必核对：`DanmakuDynamicOcclusion.kt` 里对这些类型用到的**所有**
   > 公共成员（属性/方法）都要在 lite 替身里有同名同签名声明，否则编译失败。
   > 已知用到：工厂的 `create`/`shouldAttempt`/`deviceSummary`；
   > runtime 的 `backend`/`inputWidth`/`inputHeight`/`outputWidth`/`outputHeight`/`run`/`close`。
   > 替身写好后**以编译器报错为准**逐个补齐。

### 改动 B：`android/app/build.gradle.kts`

```kotlin
android {
    // ... 现有内容 ...

    flavorDimensions += "paddle"
    productFlavors {
        create("full") {
            dimension = "paddle"
            // full 用默认 applicationId，正常发布
        }
        create("lite") {
            dimension = "paddle"
            // 让两个包能共存于同一台设备，便于对比测试（可选）
            applicationIdSuffix = ".lite"
            versionNameSuffix = "-lite"
        }
    }

    sourceSets {
        getByName("main") {
            // 现有 jniLibs 配置保持不变
            if (mpvAndroidJniLibsDir != null) {
                jniLibs.srcDir(mpvAndroidJniLibsDir)
            } else {
                jniLibs.srcDir("src/main/jniLibs")
            }
        }
        // full 打包模型资源；lite 不打包（少 13MB assets）
        getByName("full") {
            assets.srcDir("src/main/assets")        // 现有模型在 main/assets/models
        }
        getByName("lite") {
            // lite 不加模型 assets；若有其它非模型 assets 需共享，
            // 改为把模型单独挪到 src/full/assets/models 后两边都指向各自目录。
        }
    }
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.media:media:1.7.0")
    implementation("androidx.palette:palette-ktx:1.0.0")
    implementation("androidx.window:window:1.3.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    // 仅 full flavor 引入 Paddle（这是体积大头：~76MB 原生库）
    "fullImplementation"(files("libs/fastdeploy-android-sdk-latest-dev.aar"))
    testImplementation("junit:junit:4.13.2")
}
```

> 注意点：
> - 模型 assets 现在在 `src/main/assets/models`。上面 `full` sourceSet 额外指向
>   `src/main/assets` 会和 main 自身的 assets 目录**叠加**——更干净的做法是
>   **把 `src/main/assets/models` 整个移到 `src/full/assets/models`**，然后删掉上面
>   `getByName("full") { assets.srcDir(...) }` 这行（full 默认就会读 `src/full/assets`）。
>   这样 lite 天然不含模型。**推荐用移动法，避免 assets 叠加歧义。**
> - `noCompress`（pdmodel 等）保持在 `androidResources` 块，对两 flavor 都生效，无需改。

### 改动 C：模型资源归属（配合改动 B 的推荐做法）

把
```
android/app/src/main/assets/models/
```
移动到
```
android/app/src/full/assets/models/
```
lite 不需要模型，移走后 lite 包自动少 13MB assets。
（若 `assets/models` 外还有别的 main assets，只移 `models` 子目录即可。）

---

## 3. 构建命令

```bash
# 带 Paddle 的完整包（约 222MB）
flutter build apk --release --flavor full

# 不带 Paddle 的精简包（约 145MB）
flutter build apk --release --flavor lite
```

产物路径：
```
build/app/outputs/flutter-apk/app-full-release.apk
build/app/outputs/flutter-apk/app-lite-release.apk
```

> Flutter 对 flavor 的支持：`--flavor` 名称要和 `productFlavors` 里的名字一致。
> 若用 `flutter run` 也要带 `--flavor full` 或 `--flavor lite`。

---

## 4. lite 替身文件完整代码

`android/app/src/lite/kotlin/com/geqian/flyplayer/fly_player/mpv/DanmakuSegmentationRuntime.kt`

```kotlin
package com.geqian.flyplayer.fly_player.mpv

import android.content.Context
import android.graphics.Bitmap

// lite flavor：不含 Paddle/FastDeploy。保留与 full 版完全一致的对外 API，
// 但运行时一律「不可用」，使 DanmakuDynamicOcclusion 自动跳过 AI 遮挡、功能降级。
// 不 import 任何 com.baidu.paddle.* —— lite 包不依赖 fastdeploy.aar。

data class DanmakuDetectionCandidate(
    val score: Float,
    val rect: DanmakuNormalizedRect,
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

class DanmakuSegmentationRuntimeFactory(
    @Suppress("UNUSED_PARAMETER") context: Context,
    @Suppress("UNUSED_PARAMETER") paddleModelAssetDir: String,
) {
    fun create(
        backend: DanmakuAiBackend,
        config: DanmakuDynamicOcclusionConfig,
    ): DanmakuSegmentationRuntime {
        error("Paddle segmentation is not available in the lite build")
    }

    // 永远不可用 → 调用方据此跳过 AI 遮挡，功能优雅降级。
    fun shouldAttempt(backend: DanmakuAiBackend): Boolean = false

    fun deviceSummary(): String = "lite-build-no-paddle"
}

class DanmakuDetectionRuntimeFactory(
    @Suppress("UNUSED_PARAMETER") context: Context,
    @Suppress("UNUSED_PARAMETER") paddleModelAssetDir: String,
) {
    fun create(backend: DanmakuAiBackend): DanmakuDetectionRuntime {
        error("Paddle detection is not available in the lite build")
    }

    fun shouldAttempt(backend: DanmakuAiBackend): Boolean = false

    fun deviceSummary(): String = "lite-build-no-paddle"
}
```

> ⚠️ **签名核对清单**（编译前逐项对照 full 版 `DanmakuSegmentationRuntime.kt` 与
> `DanmakuDynamicOcclusion.kt` 的实际用法，缺一不可）：
> - `DanmakuSegmentationRuntimeFactory.create(backend, config)` 的第二参类型
>   `DanmakuDynamicOcclusionConfig` —— 确认该类型在 lite 也可见（它定义在
>   `DanmakuDynamicOcclusion.kt` 里，属 main sourceSet，两 flavor 都能见到，OK）。
> - `DanmakuAiBackend`、`DanmakuNormalizedRect` —— 同样定义在 main 里的
>   `DanmakuDynamicOcclusion.kt`，lite 可见，无需在替身里重复定义。
>   （所以替身里**不要**重新定义这两个类型，否则重复定义冲突。）
> - 若编译报「找不到某成员」或「重复定义」，按报错增删替身内容。

---

## 5. 验证步骤（在能正常构建的环境执行）

1. `flutter build apk --release --flavor full` → 成功，APK ≈ 旧体积（~222MB）。
2. `flutter build apk --release --flavor lite` → 成功，APK 应显著变小（~145MB）。
3. 校验 lite 包确实不含 Paddle 原生库：
   ```bash
   unzip -l build/app/outputs/flutter-apk/app-lite-release.apk | \
     grep -E "libcore_tokenizers|libpaddle|libopencv_java4|libfastdeploy|libflycv"
   # 期望：无任何输出
   ```
4. 校验 full 包仍含 Paddle：
   ```bash
   unzip -l build/app/outputs/flutter-apk/app-full-release.apk | grep libpaddle
   # 期望：有 libpaddle_full_api_shared.so
   ```
5. 装 lite 包，进播放页开弹幕 → 弹幕正常，动态遮挡（人物处不挡弹幕）不生效但不崩溃。
6. 装 full 包，验证动态遮挡正常工作。

---

## 6. 风险与回滚

- **风险**：lite 替身的 API 签名与调用方不完全一致 → 编译错误。
  解决：按编译器报错逐个补齐/删除替身成员（第 4 节清单已列已知项）。
- **风险**：assets 移动后 full 找不到模型 → 运行时 `Missing Paddle model file`。
  解决：确认模型在 `src/full/assets/models/<dir>/` 下，路径与
  `DANMAKU_AI_PADDLE_MODEL_ASSET_DIR` 常量一致。
- **回滚**：`git checkout -- android/app/build.gradle.kts` 并把
  `DanmakuSegmentationRuntime.kt` 移回 `src/main`、模型移回 `src/main/assets`，
  即恢复单包构建。

---

## 7. 备注：本次已附带完成的仓库净化（与 flavor 无关）

已删除 `jniLibs` 里的冗余（不影响 APK，但净化仓库、防未来误打包）：
- `arm64-v8a.rar`（12M 压缩包）
- `arm64-v8a/arm64-v8a/`（32M 重复 .so）
- `libold-gles/`（26M 旧备份）
并把 `.gitignore` 的 `lib.rar` 放宽为 `*.rar`。
