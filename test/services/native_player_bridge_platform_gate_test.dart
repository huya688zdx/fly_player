import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/services/native_player_bridge.dart';

/// `fly_player/native_player` 只在 Android 注册（`FlutterHostActivity
/// .registerNativePlayerChannel`），桌面与 iOS 走 media_kit、没有原生播放壳。
/// 详情页等入口的 bind 调用没有平台门控，靠桥这一层收口——这里锁住两侧行为。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('fly_player/native_player');

  Future<Map<String, dynamic>?> noopResolve(
    String itemGuid, {
    int? qualityIndex,
    String? qualityMediaGuid,
    int? startPositionMs,
    String? subtitleGuid,
    String? audioGuid,
    int? audioTrackIndex,
    int? subtitleTrackIndex,
    String? preferredQualityResolution,
  }) async => null;

  ({List<String> calls, void Function() restore}) installRecorder() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    return (
      calls: calls,
      restore: () => messenger.setMockMethodCallHandler(channel, null),
    );
  }

  test('非 Android 平台不下发 bindReentryHost，绑定降级为空转', () async {
    final recorder = installRecorder();
    addTearDown(recorder.restore);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final token = NativePlayerBridge.bindReentry(
      onResolvePlayback: noopResolve,
      onRecordProgress: (_) async {},
    );
    // 认领是 unawaited 调用：放一拍让潜在的异步异常浮出来。修复前这里会抛
    // MissingPluginException，又因无人 await 而冒到 zone 兜底，被记成 error 级日志。
    await Future<void>.delayed(Duration.zero);

    expect(token, isNotNull);
    expect(recorder.calls, isEmpty);

    // 哨兵 token 不是当前持有者，解绑同样空转、不触碰原生通道。
    NativePlayerBridge.unbindReentry(token);
    await Future<void>.delayed(Duration.zero);
    expect(recorder.calls, isEmpty);
  });

  test('Android 平台照常下发 bindReentryHost', () async {
    final recorder = installRecorder();
    addTearDown(recorder.restore);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final token = NativePlayerBridge.bindReentry(
      onResolvePlayback: noopResolve,
      onRecordProgress: (_) async {},
    );
    addTearDown(() => NativePlayerBridge.unbindReentry(token));
    await Future<void>.delayed(Duration.zero);

    expect(recorder.calls, contains('bindReentryHost'));
  });

  test('Android 上认领失败只记警告，不冒成未处理异步异常', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    // 刻意不装 mock handler：invokeMethod 会抛 MissingPluginException，等价于多 host
    // engine 下该 engine 未注册通道的情形。修复前这属于 unawaited 的未处理异常，
    // 会冒到 zone 兜底被记成 error 级日志。
    final token = NativePlayerBridge.bindReentry(
      onResolvePlayback: noopResolve,
      onRecordProgress: (_) async {},
    );
    addTearDown(() => NativePlayerBridge.unbindReentry(token));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(token, isNotNull);
  });
}
