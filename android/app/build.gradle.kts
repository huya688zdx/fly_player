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
    resolveSecretConfig("DANDANPLAY_APP_SECRET", "9XHIIK2RB9mh9YvUF8V9JECahuP9kG39")
val danDanPlayAppSecretFallback =
    resolveSecretConfig("DANDANPLAY_APP_SECRET_FALLBACK", "IBhGjXBXSqspI6UPN5Rwr5mmf3JeqJx2")
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
        noCompress += listOf("pdmodel", "pdiparams", "pdiparams.info", "yaml", "yml")
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
    implementation("androidx.window:window:1.3.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    implementation(files("libs/fastdeploy-android-sdk-latest-dev.aar"))
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
