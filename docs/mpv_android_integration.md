# mpv-android integration

This project is wired to consume native libraries built from the official `mpv-android` source tree.

## Source of truth

- Repository: [mpv-android](https://github.com/mpv-android/mpv-android)
- Official build notes: the upstream README states that native builds are supported on Linux/macOS and are not supported on Windows/WSL.

## How this project resolves native libraries

The Android app looks for `jniLibs` in these places:

1. `-PmpvAndroidDir=/absolute/path/to/mpv-android`
2. `MPV_ANDROID_DIR=/absolute/path/to/mpv-android`
3. `android/app/src/main/jniLibs`

When `mpvAndroidDir` or `MPV_ANDROID_DIR` is set, Gradle reads:

`<mpv-android>/app/src/main/jniLibs`

That matches the upstream app module layout.

## Build flow

Run the helper script on Linux or macOS:

```bash
./scripts/build_mpv_android_from_source.sh
```

Then build this app with:

```bash
cd android
./gradlew -PmpvAndroidDir=/absolute/path/to/mpv-android :app:assembleDebug
```

## Android MNN JNI 构建

`full` 风味的 `libmnnseg.so` 使用 NDK 与预编译 `libMNN.so` 外部构建。
在 `android/app` 下，使用 NDK 工具链的 `clang++`，替换头文件与库目录：

```bash
clang++ --target=aarch64-linux-android24 -std=c++14 -O2 -shared -fPIC \
  -I<mnn_include> src/full/cpp/mnn_seg_jni.cpp -o src/full/jniLibs/arm64-v8a/libmnnseg.so \
  -L<mnn_android_arm64> -lMNN -llog
```

此命令保留自原集成记录（NDK 28、MNN 3.5.0）；本次文档整理未重编译验证。

## Runtime notes

- The Android player view calls into `is.xyz.mpv.MPVLib`, matching the upstream `libplayer.so` JNI package.
- If the native libraries are missing, the Flutter player page still opens and reports that the `mpv-android` runtime is unavailable.
- Audio/subtitle selection is currently passed through as direct `aid` / `sid` assignments. Final track mapping should be validated against a real stream once playback URLs are available.
