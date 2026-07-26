#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MPV_ANDROID_DIR="${MPV_ANDROID_DIR:-$ROOT_DIR/.vendor/mpv-android}"

if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == CYGWIN* || "$(uname -s)" == MSYS* ]]; then
  echo "mpv-android native builds are not supported on Windows. Run this script on Linux or macOS."
  exit 1
fi

if [[ ! -d "$MPV_ANDROID_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/mpv-android/mpv-android.git "$MPV_ANDROID_DIR"
fi

cd "$MPV_ANDROID_DIR"

./buildscripts/download.sh
./buildscripts/buildall.sh

echo
echo "Build finished."
echo "Point this Flutter project at the repo with:"
echo "  export MPV_ANDROID_DIR=\"$MPV_ANDROID_DIR\""
echo "or pass:"
echo "  ./gradlew -PmpvAndroidDir=\"$MPV_ANDROID_DIR\" :app:assembleDebug"
