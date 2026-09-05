import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val mpvAndroidDir = providers.gradleProperty("mpvAndroidDir").orNull
    ?: System.getenv("MPV_ANDROID_DIR")

val mpvAndroidJniLibsDir = mpvAndroidDir?.let {
    file("$it/app/src/main/jniLibs")
}?.takeIf { it.exists() }

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use(::load)
    }
    val sharedSecretsFile = rootProject.file("../.look/local.properties")
    if (sharedSecretsFile.exists()) {
        sharedSecretsFile.inputStream().use(::load)
    }
}

fun resolveSecretConfig(name: String, fallback: String = ""): String {
    return providers.gradleProperty(name).orNull
        ?: localProperties.getProperty(name)
        ?: System.getenv(name)
        ?: fallback
}

fun buildConfigString(value: String): String {
    val escaped = value.replace("\\", "\\\\").replace("\"", "\\\"")
    return "\"$escaped\""
}

val danDanPlayAppId = resolveSecretConfig("DANDANPLAY_APP_ID", "mgfbs9knmv")
// 密钥不再硬编码：从 local.properties / .look/local.properties / 环境变量注入。
// 本地构建请在 android/local.properties 配置 DANDANPLAY_APP_SECRET(_FALLBACK)。
val danDanPlayAppSecret =
    resolveSecretConfig("DANDANPLAY_APP_SECRET", "")
val danDanPlayAppSecretFallback =
    resolveSecretConfig("DANDANPLAY_APP_SECRET_FALLBACK", "")
val debugKeystoreFile = rootProject.file("../.look/debug.keystore")

android {
    namespace = "com.geqian.flyplayer.fly_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        getByName("debug") {
            if (debugKeystoreFile.exists()) {
                storeFile = debugKeystoreFile
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    androidResources {
        noCompress += listOf("mnn")
    }

    buildFeatures {
        buildConfig = true
    }

    packaging {
        jniLibs {
            pickFirsts += listOf("**/libc++_shared.so")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.geqian.flyplayer.fly_player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += "arm64-v8a"
        }
        buildConfigField("String", "DANDANPLAY_APP_ID", buildConfigString(danDanPlayAppId))
        buildConfigField("String", "DANDANPLAY_APP_SECRET", buildConfigString(danDanPlayAppSecret))
        buildConfigField(
            "String",
            "DANDANPLAY_APP_SECRET_FALLBACK",
            buildConfigString(danDanPlayAppSecretFallback),
        )
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }

        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles("proguard-rules.pro")
        }

        // profile 性能分析包：独立 applicationId（.profile 后缀），
        // 与正式包共存于同一设备，互不覆盖、不占用对方数据。
        getByName("profile") {
            initWith(getByName("release"))
            matchingFallbacks += listOf("release")
            applicationIdSuffix = ".profile"
            versionNameSuffix = "-profile"
            signingConfig = signingConfigs.getByName("debug")
            // profile 包定位是性能分析，不做 R8 瘦身（本工程 R8 会编译失败）；
            // 资源收缩依赖代码收缩，需一并关闭。
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // 两个产品风味：
    //   full —— 含 MNN 弹幕动态遮挡（ISNet-anime，~8MB 原生库 + ~85MB 模型）。
    //   lite —— 不含遮挡，APK 约 58MB；动态遮挡自动降级为不可用（不崩溃）。
    //   注意：build 输出目录里的旧 APK 会因增量构建残留孤立数据而虚胖，
    //   看真实包体请以 clean 后的单次构建为准（见 docs 或 memory 记录）。
    // MNN 实现/模型/.so 按 sourceSet 隔离在 src/full，lite 用 src/lite 同 API 替身。
    flavorDimensions += "paddle"
    productFlavors {
        create("full") {
            dimension = "paddle"
        }
        create("lite") {
            dimension = "paddle"
            // 允许与 full 包共存于同一台设备，便于对比测试。
            applicationIdSuffix = ".lite"
            versionNameSuffix = "-lite"
        }
    }

    sourceSets {
        getByName("main") {
            if (mpvAndroidJniLibsDir != null) {
                jniLibs.srcDir(mpvAndroidJniLibsDir)
            } else {
                jniLibs.srcDir("src/main/jniLibs")
            }
        }
    }
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.media:media:1.7.0")
    implementation("androidx.palette:palette-ktx:1.0.0")
    implementation("androidx.window:window:1.5.0")
    implementation("com.github.bumptech.glide:glide:4.16.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    // Paddle/FastDeploy 已移除（换成 MNN，原生库从 ~76MB 降到 ~7MB）。
    // full flavor 的 MNN .so + 模型按 sourceSet 隔离在 src/full（jniLibs/assets），
    // 无需在此声明依赖。
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("org.json:json:20240303")
}

flutter {
    source = "../.."
}
