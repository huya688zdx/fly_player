# 已下载视频播放时选集网络封面修复实施记录

**目标：** 修复从下载列表播放时未下载集封面为黑图的问题，并消除选集面板打开后的二次闪烁。

**最终根因：** Flutter payload 已包含网络封面和鉴权头；Android 原生图片请求不接受 NAS 私有/自签名证书，触发 `SSLHandshakeException`。证书修复后，静默刷新无条件重建面板又造成一次可见闪烁。

**实现边界：** 只对携带 NAS 鉴权头的 HTTPS 图片兼容私有证书；无鉴权头图片仍使用系统证书校验。敏感头只允许同源重定向。面板仅在加载态或内容确有变化时重绘。

## 已完成步骤

- [x] 验证 Flutter `poster`、`imageHeaders`、`imageAuth` 数据链路。
- [x] 真机诊断确认未下载集图片失败类型为 `SSLHandshakeException`。
- [x] 先添加失败测试，覆盖私网地址、自定义 HTTPS 域名、HTTP 拒绝和无效 URL。
- [x] 新增 `NativeAuthenticatedImageTlsPolicy`，并在 `NativeSafeImageHttp` 的鉴权 HTTPS 分支使用私有证书客户端。
- [x] 先添加失败测试，覆盖稳定内容不重复重绘的决策。
- [x] 调整选集静默刷新：仅在加载态结束或内容变化时重绘。
- [x] 运行 Flutter 图片字段测试和静态分析。
- [x] 运行 Android 图片头、重定向、TLS 策略和面板模型单元测试。
- [x] 构建并覆盖安装 full debug APK。
- [x] 真机确认未下载集封面全部返回 200，选集连续开关不再闪烁。
- [x] 移除所有临时诊断日志。

## 最终验证命令

```powershell
flutter test test/nas_image_headers_test.dart test/services/native_reentry_support_test.dart
flutter analyze lib/utils/nas_image_headers.dart lib/services/native_reentry_support.dart lib/controllers/item_playback_launcher.dart test/nas_image_headers_test.dart test/services/native_reentry_support_test.dart
android\gradlew.bat -p android :app:testFullDebugUnitTest --tests "com.geqian.flyplayer.fly_player.NativeAuthenticatedImageTlsPolicyTest" --tests "com.geqian.flyplayer.fly_player.NativeImageRequestHeadersTest" --tests "com.geqian.flyplayer.fly_player.NativeImageRedirectPolicyTest" --tests "com.geqian.flyplayer.fly_player.NativePlayerActivityPanelModelsTest.episodeRefreshMergeCompletesDownloadedFallbackWithNetworkPosters" --tests "com.geqian.flyplayer.fly_player.NativePlayerActivityPanelModelsTest.episodeRefreshMergeDoesNotClearExistingPosterWithEmptyIncomingValue" --tests "com.geqian.flyplayer.fly_player.NativePlayerActivityPanelModelsTest.episodeRefreshRenderDecisionSkipsStableSettledContent"
flutter build apk --debug --flavor full
```

完整执行 `NativePlayerActivityPanelModelsTest` 时，11 个既有本地化文案用例会在测试夹具构造的无基座 `Application` 调用 `NativeLocalizedStrings.resolve()` 时 NPE；单独运行其中任一用例也可复现。该问题不经过本次图片或刷新逻辑，未在本提交中扩展范围修复。
