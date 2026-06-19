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
val danDanPlayAppSecret =
    resolveSecretConfig("DANDANPLAY_APP_SECRET", "***REMOVED-DANDANPLAY-SECRET***")
val danDanPlayAppSecretFallback =
    resolveSecretConfig("DANDANPLAY_APP_SECRET_FALLBACK", "***REMOVED-DANDANPLAY-SECRET***")
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
    }

    // 两个产品风味：
    //   full —— 含 MNN 弹幕动态遮挡（ISNet-anime，~7MB 原生库 + ~88MB 模型）。
    //   lite —— 不含遮挡，包体小 ~95MB；动态遮挡自动降级为不可用（不崩溃）。
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
}

flutter {
    source = "../.."
}
