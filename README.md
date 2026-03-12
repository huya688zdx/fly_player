# Fly Player

基于 Flutter 开发的 Android 播放器，面向飞牛 NAS 媒体库场景，集成 `mpv-android` 作为原生播放内核。

当前项目重点是：

- 飞牛 NAS 连接与媒体浏览
- 媒体详情页与剧集入口
- 基于 `mpv` 的 Android 播放页
- 清晰度、音频、字幕切换
- 手势控制、章节进度线、OP/ED 跳过

## 技术栈

- Flutter
- Provider
- Dio
- SharedPreferences
- mpv-android native runtime

## 主要功能

### 媒体与详情

- 连接飞牛 NAS 服务
- 浏览媒体列表与媒体库
- 进入影视详情页、季详情页、剧集页

### 播放器

- 原生 `mpv` 播放核心
- 本地代理转发播放流
- 清晰度切换
- 音频轨切换
- 字幕轨切换与外部字幕处理
- 播放进度条章节标记
- 左右滑动快进快退
- 左右区域上下滑动调节亮度和音量
- 长按临时双倍速
- 中央加载态和状态提示

### 进阶播放能力

- 片头片尾跳过
  - 飞牛官方跳过配置
  - 按章节自动判断
  - 按章节手动选择
- 播放器设置抽屉
- 原生解码与显示比例控制

## 项目结构

```text
lib/
  api/            飞牛接口封装
  controllers/    详情页数据与交互控制器
  models/         播放、媒体、字幕等数据模型
  pages/          页面级入口
  player/         mpv 播放器主体与各类 mixin / overlay / drawer
  providers/      全局状态
  screens/        列表与业务页面
  ui/             通用界面能力
  utils/          工具函数
  widgets/        业务组件

android/app/src/main/kotlin/.../mpv/
  mpv 原生桥接、播放控制、恢复、诊断、代理服务
```

## 环境要求

- Flutter SDK `3.11.0` 或兼容版本
- Android 开发环境
- JDK / Android SDK / Gradle

## 运行方式

### 1. 获取依赖

```bash
flutter pub get
```

### 2. 运行调试包

```bash
flutter run
```

### 3. 打 debug APK

```bash
flutter build apk --debug
```

产物默认在：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## mpv 原生库说明

本项目 Android 播放能力依赖 `mpv-android` 对应 native 库。

当前仓库已经包含 `android/app/src/main/jniLibs/` 下的必要 `.so` 文件，因此默认可以直接构建和运行，不需要先手动编译 `mpv-android`。

如果你要自己替换或从上游重新构建，可参考：

- [docs/mpv_android_integration.md](./docs/mpv_android_integration.md)
- [scripts/build_mpv_android_from_source.sh](./scripts/build_mpv_android_from_source.sh)

## 配置说明

应用首次启动后，需要先配置飞牛 NAS 连接信息。配置完成后才会进入媒体列表和播放流程。

## 当前仓库状态

这个仓库目前以 Android 播放链路和 Flutter 界面联动为主，播放器部分迭代较快，后续仍会继续整理：

- `README` 与使用说明
- 播放器高级设置结构
- 原生播放诊断与兼容性选项
- 播放器页面内部模块拆分与清理

## 相关文档

- [mpv Android 集成说明](./docs/mpv_android_integration.md)
