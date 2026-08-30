import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'playback_poc_screen.dart';

/// 桌面播放内核 PoC 的独立入口，不接入现有路由与播放器宿主。
///
/// 示例：
/// flutter run -d windows -t lib/desktop/playback/poc_main.dart
///   --dart-define=POC_MEDIA_URL=<本地文件绝对路径或网络地址>
///   --dart-define=POC_BENCHMARK_COMMENTS=300
///   --dart-define=POC_HTTP_HEADERS_FILE=<仓库外 JSON 文件绝对路径>
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  const mediaUrl = String.fromEnvironment('POC_MEDIA_URL');
  const benchmarkComments = int.fromEnvironment(
    'POC_BENCHMARK_COMMENTS',
    defaultValue: 0,
  );
  const httpHeadersFilePath = String.fromEnvironment('POC_HTTP_HEADERS_FILE');

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      home: PlaybackPocScreen(
        mediaUrl: mediaUrl,
        benchmarkComments: benchmarkComments,
        httpHeadersFilePath: httpHeadersFilePath,
      ),
    ),
  );
}
