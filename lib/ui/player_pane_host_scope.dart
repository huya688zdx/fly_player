import 'package:flutter/widgets.dart';

import '../models/play_info.dart';
import '../player/controllers/mpv_player_controller.dart';
import '../services/play_stats/play_stats.dart';

abstract class PlayerPaneHostController {
  Future<bool> openRoute(String routeName);

  Future<bool> backInPane();

  Future<bool> closePane();

  Future<bool> replacePlayerSource({
    required String title,
    required MpvMediaSource source,
    PlayInfoData? initialPlayInfo,
    PlayStartSource startSource = PlayStartSource.manual,
  });
}

class PlayerPaneHostScope extends InheritedWidget {
  final PlayerPaneHostController controller;

  const PlayerPaneHostScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static PlayerPaneHostController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PlayerPaneHostScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(PlayerPaneHostScope oldWidget) {
    return controller != oldWidget.controller;
  }
}
