import 'package:shared_preferences/shared_preferences.dart';

/// 管理播放列表视图类型偏好的本地缓存读写。
///
/// shared_preferences 落盘为 `flutter.playlist_view_type`，原生壳
/// NativePlayerActivity 直接读同一文件同一键——三端共用一份、不漂移，key 名不可变更。
/// 本类是该 key 在 Dart 侧的唯一权威读写入口，飞牛与服务器族（Emby 等）选集面板
/// 均应委托本类，不得各自平行读写 SharedPreferences。
class PlaylistViewPreferenceStore {
  static const String viewTypeKey = 'playlist_view_type';
  static const String viewTypeCard = 'card';
  static const String viewTypeButton = 'button';

  /// 创建一个播放列表视图偏好存储实例。
  const PlaylistViewPreferenceStore();

  /// 读取本地缓存的播放列表视图类型；无缓存或值非法时返回 null。
  Future<String?> readViewType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(viewTypeKey)?.trim();
      return (v == viewTypeButton || v == viewTypeCard) ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// 写入播放列表视图类型到本地缓存；非法值静默丢弃不写入。
  Future<void> writeViewType(String viewType) async {
    if (viewType != viewTypeButton && viewType != viewTypeCard) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(viewTypeKey, viewType);
    } catch (_) {
      // 本地缓存写失败不影响服务端真值。
    }
  }
}
