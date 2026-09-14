# Linux 播放开发与验证

当前分支接通 Windows/Linux 共用的桌面播放宿主，包含条目详情、剧集和本地下载入口。播放页、音轨字幕、弹幕、切集和进度上报继续使用现有桌面实现。

Linux 使用 GTK 原生标题栏和 media_kit 的原生全屏接口。凭据使用 `flutter_secure_storage_linux` 提供的 Secret Service 密钥环；SQLite、文件选择和下载路径沿用已有桌面实现。

Windows 已通过 87 项相关测试和 11 个改动文件的静态检查。2026-09-10 在 Ubuntu 24.04.4 桌面虚拟机上完成了首轮 Linux 验证：35 项相关测试、11 个文件的静态检查和正式 Release 编译均通过，正式应用已显示媒体服务登录页。

设备验证使用临时入口直接复用 `DesktopPlaybackScreen`、`DesktopPlaybackSession` 和 `LinuxSecureCredentialBackend`，未修改正式入口。合成的 1280×720 H.264/AAC 短视频通过首帧渲染、暂停、拖到 3 秒后继续播放至 4 秒和截图检查；真实密钥环的写入、读取、删除均通过。音频输出为 PipeWire，48 kHz 单声道；本次未验收远程实际听音。

虚拟机当前使用软件解码和软件渲染，media_kit 的 EGL 路径不可用后回退到软件输出。以上结果不能证明真机硬解、HDR、实际 NAS 登录、切集和服务端进度上报通过。

本次独立正式测试包位于 Linux 的 `/home/flutter/fly-player-linux-release-20260910`，应用菜单入口为“飞翔播放器 Linux 测试版”。临时设备验证程序不包含在该正式包中。

## 开发环境

先以 Ubuntu 24.04 LTS 桌面环境为基准。其他发行版安装对应的软件包；CPU 架构确定后，在目标架构的 Linux 上构建。

使用 Flutter 官方压缩包安装 SDK，并与当前开发环境的 Flutter 3.41.6 / Dart 3.11.4 对齐。避免使用 Snap 版 Flutter 与系统 libsecret 的不同 GLib 版本混用。

在 Ubuntu 24.04 上安装依赖：

```bash
sudo apt-get update
sudo apt-get install -y git curl unzip xz-utils clang lld cmake ninja-build \
  pkg-config libgtk-3-dev libstdc++-12-dev libmpv-dev libepoxy-dev \
  libsecret-1-dev libsqlite3-0 liblzma-dev
```

Ubuntu 24.04 的 clang 18 还需要匹配的 `lld-18`（上面的 `lld` 包会提供默认版本）。本次首次正式构建报找不到 `/usr/lib/llvm-18/bin/ld.lld` 或 `ld`，补装 `lld-18` 后构建通过。

还需要已登录的图形桌面会话、可用的 OpenGL 驱动和声音服务，以及已解锁的桌面密钥环。Ubuntu GNOME 通常已提供 GNOME Keyring；如果密钥环不可用，应用保留凭据读取失败状态，不能用明文存储替代。

`media_kit_libs_linux` 不把整套 libmpv 打包进应用；构建和运行都依赖发行版的 libmpv。插件首次构建还会从 GitHub 下载 mimalloc。

## 编译运行

把本分支代码放到 Linux 文件系统，进入项目目录执行：

```bash
flutter doctor -v
flutter pub get
flutter analyze --no-pub lib/services/secure_credential_store_linux.dart
flutter test --no-pub --concurrency=1 \
  test/services/secure_credential_store_test.dart \
  test/desktop/desktop_playback_runtime_test.dart \
  test/controllers/local_download_source_resolver_test.dart
flutter build linux --release
```

x86_64 设备的启动命令：

```bash
./build/linux/x64/release/bundle/fly_player
```

也可在图形桌面终端运行 `flutter run -d linux --release`。分发时复制整个 `bundle` 目录，并在目标机器安装 libmpv、GTK、libsecret 等运行库；只复制可执行文件无法运行。

## 设备验收

1. 使用飞牛或 Emby/Jellyfin 的直连服务器地址登录，退出应用再打开，确认凭据恢复和首页加载。
2. 从详情和剧集页播放，确认真实画面、声音、暂停、拖动、空格/F/Esc、全屏退出和关闭播放页。
3. 确认音轨字幕切换、外挂字幕、弹幕、截图保存、下一集及返回后恢复进度。
4. 下载一集后断开 NAS，确认下载入口播放本地文件及本地切集。
5. 分别验证软件解码和硬件解码；硬解默认交给 mpv 的 `auto-safe` 选择。记录发行版、CPU/GPU、X11/Wayland、驱动和 mpv 版本。

## 当前边界

- 飞牛 FN Connect 网页授权、Emby FN 入口的嵌入式网页登录尚无 Linux WebView 后端。本轮先验收直连 API 登录，不把这些网页授权路径列为已支持。
- macOS 未开放播放；Android 动态遮罩、系统画中画等原生功能不属于本次 Linux 接入。
- 原生 Linux 硬解、HDR、音频直通和不同桌面显示协议的表现需要设备证据，Windows 测试不能代替。

依赖依据：[Flutter Linux 环境](https://docs.flutter.dev/platform-integration/linux/setup)、[media_kit](https://github.com/media-kit/media-kit)、[Linux 密钥环插件](https://pub.dev/packages/flutter_secure_storage_linux)。
