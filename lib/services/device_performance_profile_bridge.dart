import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class DevicePerformanceProfile {
  const DevicePerformanceProfile({required this.isLowRamDevice});

  const DevicePerformanceProfile.unknown() : isLowRamDevice = false;

  final bool isLowRamDevice;
}

/// 只读取 Android 官方低内存标记；未知设备按均衡档处理。
class DevicePerformanceProfileBridge {
  DevicePerformanceProfileBridge._();

  static const MethodChannel _channel = MethodChannel('fly_player/system');
  static Future<DevicePerformanceProfile>? _inFlight;
  static DevicePerformanceProfile? _cached;

  static Future<DevicePerformanceProfile> load() {
    final cached = _cached;
    if (cached != null) {
      return Future<DevicePerformanceProfile>.value(cached);
    }
    return _inFlight ??= _load();
  }

  static Future<DevicePerformanceProfile> _load() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getDevicePerformanceProfile',
      );
      final profile = DevicePerformanceProfile(
        isLowRamDevice: result?['isLowRamDevice'] == true,
      );
      _cached = profile;
      return profile;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[UI][PERFORMANCE] profile unavailable: $error');
      }
      return const DevicePerformanceProfile.unknown();
    } finally {
      _inFlight = null;
    }
  }
}
