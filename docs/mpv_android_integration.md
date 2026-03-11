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

## Runtime notes

- The Android player view calls into `is.xyz.mpv.MPVLib`, matching the upstream `libplayer.so` JNI package.
- If the native libraries are missing, the Flutter player page still opens and reports that the `mpv-android` runtime is unavailable.
- Audio/subtitle selection is currently passed through as direct `aid` / `sid` assignments. Final track mapping should be validated against a real stream once playback URLs are available.
