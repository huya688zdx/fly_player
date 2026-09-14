# iOS / macOS 适配

本分支从 `main` 的 `e2c478f` 创建，未合入其他工作目录的未提交改动。Apple 工程使用 Flutter **3.41.9 / Dart 3.11** 模板，iOS 最低 **13.0**，macOS 最低 **10.15**。

## 已实现的代码路径

| 能力 | iOS | macOS |
| --- | --- | --- |
| 应用工程 | Swift Runner、UIScene、CocoaPods | Swift Runner、CocoaPods、沙盒权限 |
| 在线 / 已下载媒体播放 | media_kit，触控操作和安全区布局 | media_kit，桌面操作和原生全屏 |
| 换集、画质、音轨、字幕、播放记录 | 复用已有播放宿主和上报流程 | 复用已有播放宿主和上报流程 |
| 账户凭据 | Keychain | Keychain |
| 数据库 | sqflite_darwin | sqflite_darwin |
| 文件选择 | 系统文件选择器导入沙盒 | 系统文件选择器 |
| 默认下载目录 | 应用 Documents/Downloads/FlyPlayer | 系统 Downloads/FlyPlayer |
| 截图 | 播放器内另存为文件 | 播放器内另存为文件 |
| 搜索快捷键 | 保留移动端交互 | Command+K，兼容 Ctrl+K |

凭据读取区分不存在和暂时不可用：Keychain 锁定或返回错误时不会把它误判为退出登录。两平台共享 `ios/Runner/AppleCredentialStore.swift`，macOS 工程直接引用该文件；移动目录时请同时保留两个工程。

NAS 地址由用户填写，工程允许 HTTP NAS 和网页登录，并配置本地网络访问用途说明。macOS 开启应用沙盒、网络客户端、用户所选文件读写和 Downloads 读写；调试配置额外允许 Flutter 调试所需的网络服务端和 JIT。

macOS 当前仅使用默认下载位置。任意自选目录若要在重启后继续使用，需要额外实现 security-scoped bookmark，因此没有开放自定义下载目录入口，也不消费旧的自定义目录偏好。iOS 使用沙盒下载目录，可从「文件」App 中访问 Documents。

## 在 Mac 上编译和验证

安装 Flutter 3.41.9、兼容的 Xcode 和 CocoaPods，然后在本工作目录执行：

```bash
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build ios --simulator --debug
flutter build macos --debug
```

模拟器构建不需要配置个人开发团队。真机运行和分发前，在 Xcode 中打开 `ios/Runner.xcworkspace` 或 `macos/Runner.xcworkspace`，选择自己的签名团队；工程未写入任何开发者身份。Apple 编译工具链需要 macOS/Xcode，参见 [Flutter 平台设置](https://docs.flutter.dev/platform-integration)。

原生凭据测试使用注入的 Keychain 替身，不读写真实账户。先完成上述构建和 Pods 安装，再运行 macOS 测试：

```bash
xcodebuild -workspace macos/Runner.xcworkspace \
  -scheme Runner -destination 'platform=macOS' test
```

iOS 在 Xcode 中选定一个可用模拟器后执行 Product → Test，或用 `xcodebuild -showdestinations -workspace ios/Runner.xcworkspace -scheme Runner` 查询目标，再以相应 `-destination` 执行 `test`。

## 弹幕凭据

Apple 构建通过 `--dart-define` 注入 `DANDANPLAY_APP_ID`、`DANDANPLAY_APP_SECRET` 和可选的 `DANDANPLAY_APP_SECRET_FALLBACK`。也可使用未纳入版本控制的 `--dart-define-from-file` JSON 文件。未配置时弹幕服务显示未配置状态，普通媒体播放仍可使用。Apple 不读取 Android `local.properties` 或 Windows 开发目录。

## 本次验证范围与后续实机检查

代码在 Windows 上完成 Flutter 测试和静态检查；这里未执行 Apple 原生编译、Swift XCTest、签名或真机播放，不能据此视为已经通过 iOS/macOS 发布验收。

2026-09-12 本地验证：完整 Flutter 测试 **1,220 项通过**；`flutter analyze --no-pub` 无问题；Apple 工程的 19 个 XML 文件、PBX 源码引用、最低系统版本、Pods 配置和插件注册静态检查通过。触控回归覆盖长时间拖动进度条、多点触摸、取消触摸及点击显示/隐藏控制栏。

Mac 端验收应覆盖：首次登录及重启恢复、HTTP/HTTPS NAS 与网页登录、本地网络权限拒绝和重试、在线视频和下载文件播放、拖动进度、外挂字幕、画质/音轨/剧集切换、播放记录回写、截图另存、下载和日志导出、iPhone 横竖屏安全区、macOS 全屏进出。

本阶段未接入 iOS 后台下载、画中画、系统媒体控制中心、Android MediaStore 截图库或 Android AI 弹幕遮挡。Android 专属文件权限和目录树接口在 Apple 平台不会调用；截图保存使用播放器自身的文件导出流程。

Apple 应用图标目前沿用 Flutter 工程模板，发行打包前需替换品牌图标。
