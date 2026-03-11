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

android {
    namespace = "com.geqian.flyplayer.fly_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

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
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.nanohttpd:nanohttpd:2.3.1")
}

flutter {
    source = "../.."
}
