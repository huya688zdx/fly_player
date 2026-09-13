import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/app_theme.dart';
import '../desktop_floating_panel.dart';
import 'external_playback_host.dart';
import 'external_playback_mini_settings.dart';

/// 常用控制直接操作当前 PotPlayer 会话，不另起播放或进度计时。
class ExternalPlaybackMiniPlayer extends StatefulWidget {
  const ExternalPlaybackMiniPlayer({
    super.key,
    required this.expanded,
    this.settingsExpanded = false,
    this.pinned = true,
    this.onTogglePinned,
    required this.onToggleExpanded,
    this.onToggleSettings,
    required this.onRestore,
  });

  final bool expanded;
  final bool settingsExpanded;
  final bool pinned;
  final Future<void> Function()? onTogglePinned;
  final Future<void> Function() onToggleExpanded;
  final Future<void> Function()? onToggleSettings;
  final Future<void> Function() onRestore;

  @override
  State<ExternalPlaybackMiniPlayer> createState() =>
      _ExternalPlaybackMiniPlayerState();
}

class _ExternalPlaybackMiniPlayerState
    extends State<ExternalPlaybackMiniPlayer> {
  bool _busy = false;
  String? _error;
  double? _seekPosition;

  Future<void> _run(Future<bool?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await action() == false && mounted) {
        setState(() => _error = '操作未完成，请在完整页面检查连接');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '操作失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _windowAction(Future<void> Function() action) async {
    // 切集可能等待网络，仍然允许随时收起或返回完整界面。
    if (_error != null) setState(() => _error = null);
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = '窗口调整失败，请重试');
    }
  }

  static String _time(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999);
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: ExternalPlaybackHost.status,
    builder: (context, status, _) {
      final colors = context.appColors;
      // 命令执行时仅阻止重复提交，保持整组按钮的颜色和布局稳定。
      final enabled = status?.canControl == true;
      final title = status?.source.title ?? '当前播放已结束';
      final itemGuid = status?.source.itemGuid ?? '';
      final current =
          status?.playlist.indexWhere((e) => e.itemGuid == itemGuid) ?? -1;
      final phase = switch (status?.phase) {
        ExternalPlaybackPhase.ready => status!.paused ? '已暂停' : '播放中',
        ExternalPlaybackPhase.preparing => '正在连接',
        ExternalPlaybackPhase.disconnected => '连接已断开',
        _ => '播放已结束',
      };

      void pause() => _run(
        () =>
            ExternalPlaybackHost.setPaused(!status!.paused, itemGuid: itemGuid),
      );
      void seek(Duration target) =>
          _run(() => ExternalPlaybackHost.seek(target, itemGuid: itemGuid));
      void step(int direction) => _run(
        () => ExternalPlaybackHost(context).playEpisode(
          itemGuid: itemGuid,
          episodeGuid: status!.playlist[current + direction].itemGuid,
        ),
      );

      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _windowAction(widget.onRestore),
          if (enabled) const SingleActivator(LogicalKeyboardKey.space): pause,
        },
        child: Focus(
          autofocus: true,
          child: ColoredBox(
            color: colors.backgroundBase,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: DesktopFloatingPanel(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 56,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              Semantics(
                                label: '拖动悬浮条',
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (_) =>
                                      windowManager.startDragging(),
                                  child: SizedBox(
                                    width: 24,
                                    height: 44,
                                    child: Icon(
                                      Icons.drag_indicator_rounded,
                                      size: 18,
                                      color: colors.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (_) =>
                                      windowManager.startDragging(),
                                  onTap: () =>
                                      _windowAction(widget.onToggleExpanded),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 7,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: colors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _error ??
                                              '$phase · ${_time(status?.position ?? Duration.zero)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: _error == null
                                                ? colors.textMuted
                                                : colors.danger,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _button(
                                status?.paused == false
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                status?.paused == false ? '暂停' : '继续',
                                enabled ? pause : null,
                                primary: true,
                              ),
                              _button(
                                widget.pinned
                                    ? Icons.push_pin_rounded
                                    : Icons.push_pin_outlined,
                                widget.pinned ? '取消置顶' : '置顶悬浮条',
                                widget.onTogglePinned == null
                                    ? null
                                    : () =>
                                          _windowAction(widget.onTogglePinned!),
                                primary: widget.pinned,
                              ),
                              _button(
                                widget.expanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                widget.expanded ? '收起操作' : '展开操作',
                                () => _windowAction(widget.onToggleExpanded),
                              ),
                              _button(
                                Icons.open_in_full_rounded,
                                '返回完整界面',
                                () => _windowAction(widget.onRestore),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.expanded) ...[
                        Divider(height: 1, color: colors.borderSubtle),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Text(
                                _time(status?.position ?? Duration.zero),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.textMuted,
                                ),
                              ),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 5,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 10,
                                    ),
                                  ),
                                  child: Slider(
                                    value:
                                        (_seekPosition ??
                                                status?.position.inMilliseconds
                                                    .toDouble() ??
                                                0)
                                            .clamp(
                                              0,
                                              (status
                                                          ?.duration
                                                          .inMilliseconds ??
                                                      0)
                                                  .clamp(1, 360000000)
                                                  .toDouble(),
                                            ),
                                    max: (status?.duration.inMilliseconds ?? 0)
                                        .clamp(1, 360000000)
                                        .toDouble(),
                                    onChanged: enabled
                                        ? (value) => setState(
                                            () => _seekPosition = value,
                                          )
                                        : null,
                                    onChangeEnd: enabled
                                        ? (value) {
                                            setState(
                                              () => _seekPosition = null,
                                            );
                                            seek(
                                              Duration(
                                                milliseconds: value.round(),
                                              ),
                                            );
                                          }
                                        : null,
                                  ),
                                ),
                              ),
                              Text(
                                _time(status?.duration ?? Duration.zero),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _button(
                              Icons.skip_previous_rounded,
                              '上一集',
                              enabled && current > 0 ? () => step(-1) : null,
                            ),
                            const SizedBox(width: 18),
                            _button(
                              Icons.replay_10_rounded,
                              '后退 10 秒',
                              enabled
                                  ? () => seek(
                                      status!.position -
                                          const Duration(seconds: 10),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 18),
                            _button(
                              Icons.forward_10_rounded,
                              '前进 10 秒',
                              enabled
                                  ? () => seek(
                                      status!.position +
                                          const Duration(seconds: 10),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 18),
                            _button(
                              Icons.skip_next_rounded,
                              '下一集',
                              enabled &&
                                      current >= 0 &&
                                      current + 1 < status!.playlist.length
                                  ? () => step(1)
                                  : null,
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 7, 12, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      status?.danmakuEnabled == true
                                      ? colors.accent
                                      : colors.textSecondary,
                                  textStyle: const TextStyle(fontSize: 11),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: enabled
                                    ? () => _run(
                                        () => ExternalPlaybackHost.applyDanmaku(
                                          itemGuid: itemGuid,
                                          enabled: !status!.danmakuEnabled,
                                        ),
                                      )
                                    : null,
                                icon: Icon(
                                  status?.danmakuEnabled == true
                                      ? Icons.subtitles_rounded
                                      : Icons.subtitles_off_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  status?.danmakuEnabled == true
                                      ? '弹幕已开'
                                      : '弹幕已关',
                                ),
                              ),
                              _button(
                                Icons.tune_rounded,
                                '弹幕与字幕调节',
                                widget.onToggleSettings == null
                                    ? null
                                    : () => _windowAction(
                                        widget.onToggleSettings!,
                                      ),
                                primary: widget.settingsExpanded,
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  textStyle: const TextStyle(fontSize: 11),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: enabled
                                    ? () => _run(
                                        () =>
                                            ExternalPlaybackHost.activateCurrent(
                                              itemGuid: itemGuid,
                                            ),
                                      )
                                    : null,
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 14,
                                ),
                                label: const Text('回到 PotPlayer'),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            _error ?? status?.progressMessage ?? '返回完整界面选择影片',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: _error == null
                                  ? colors.textMuted
                                  : colors.danger,
                            ),
                          ),
                        ),
                      ],
                      if (status != null)
                        Visibility(
                          visible: widget.expanded && widget.settingsExpanded,
                          maintainState: true,
                          child: ExternalPlaybackMiniSettings(
                            key: ValueKey(
                              '${status.source.itemGuid}:${status.source.mediaGuid}',
                            ),
                            status: status,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _button(
    IconData icon,
    String label,
    VoidCallback? action, {
    bool primary = false,
  }) {
    final colors = context.appColors;
    return IconButton(
      key: ValueKey(
        'external-mini-${icon == Icons.pause_rounded || icon == Icons.play_arrow_rounded ? 'play-pause' : label}',
      ),
      onPressed: action,
      style: IconButton.styleFrom(
        fixedSize: const Size(32, 32),
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: primary ? colors.accent : colors.textSecondary,
        backgroundColor: primary ? colors.accentSoft : Colors.transparent,
        iconSize: primary ? 21 : 18,
        overlayColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      icon: Icon(icon, semanticLabel: label),
    );
  }
}
