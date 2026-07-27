import 'package:shared_preferences/shared_preferences.dart';

/// 管理播放列表视图类型偏好的本地缓存读写。
///
/// shared_preferences 落盘为 `flutter.playlist_view_type`，原生壳
/// NativePlayerActivity 直接读同一文件同一键——三端共用一份、不漂移，key 名不可变更。
class PlaylistViewPreferenceStore {
  static const String _viewTypePrefKey = 'playlist_view_type';

  /// 创建一个播放列表视图偏好存储实例。
  const PlaylistViewPreferenceStore();

  /// 读取本地缓存的播放列表视图类型；无缓存或值非法时返回 null。
  Future<String?> readViewType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_viewTypePrefKey)?.trim();
      return (v == 'button' || v == 'card') ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// 写入播放列表视图类型到本地缓存。
  Future<void> writeViewType(String viewType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewTypePrefKey, viewType);
    } catch (_) {
      // 本地缓存写失败不影响服务端真值。
    }
  }
}
