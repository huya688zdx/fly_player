# webview_windows 本地副本

来源：[jnschulze/flutter-webview-windows](https://github.com/jnschulze/flutter-webview-windows) 的 pub.dev `webview_windows 0.4.0`。保留构建所需的 `lib/`、`windows/`、`pubspec.yaml` 和上游 BSD 3-Clause `LICENSE`。

为飞翔通过 FN 网关访问增加 `WebviewController.getCookies(String uri)`，使用当前 WebView2 实例的 CookieManager。仅接受无账号、查询、片段或非默认端口的 HTTPS `*.fnos.net/app/fly-data-service/api/v1/system/identity` 地址；仅返回 `entry-token`、`mode`、`ost` 及其作用域属性，不返回网页业务会话或其他 Cookie。调用方不得记录值，持久化必须使用平台安全凭据存储。

相对上游仅有四个功能修改文件：

- `lib/src/webview.dart`：受限 Dart 接口及返回名称过滤。
- `windows/webview.h`：Cookie 结果和回调声明。
- `windows/webview.cc`：CookieManager 读取、URI 限制及名称过滤。
- `windows/webview_bridge.cc`：方法通道映射。

另按当前 Flutter SDK 格式化 `lib/src/enums.dart`、`lib/src/webview.dart`，其中 `enums.dart` 仅有格式变化；清理 `windows/util/rohelper.cc`、`rohelper.h` 各一处上游注释的行尾空格。其余 WebView 行为和依赖版本沿用上游；未包含示例、缓存或构建产物。
