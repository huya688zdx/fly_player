import 'external_player_adapter.dart';
import 'potplayer_adapter.dart';

/// 当前随桌面端提供的外部播放器实现。
abstract final class ExternalPlayerAdapters {
  static const defaultId = 'potplayer';
  static const defaultPlayer = PotPlayerAdapter();
  static const available = <ExternalPlayerAdapter>[defaultPlayer];

  static ExternalPlayerAdapter forId(String id) {
    for (final player in available) {
      if (player.id == id) return player;
    }
    throw StateError('不支持的外部播放器：$id');
  }
}
