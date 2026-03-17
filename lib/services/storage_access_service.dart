import 'package:flutter/services.dart';

class StorageAccessService {
  static const MethodChannel _channel = MethodChannel('fly_player/storage');

  static Future<bool> hasFileAccess() async {
    final result = await _channel.invokeMethod<bool>('hasFileAccess');
    return result == true;
  }

  static Future<bool> requestFileAccess() async {
    final result = await _channel.invokeMethod<bool>('requestFileAccess');
    return result == true;
  }

  static Future<String> primaryStorageRoot() async {
    final path = await _channel.invokeMethod<String>('getPrimaryStorageRoot');
    return (path ?? '/storage/emulated/0').trim();
  }
}
