import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/app_theme.dart';
import '../desktop_floating_panel.dart';
import 'desktop_playback_mini_controller.dart';

/// 置顶迷你条：拖动换位 + 集名 + 上一集/±15s/播停/下一集 + 置顶徽标 + 还原。
/// 命令直接调播放页注册的控制面（`DesktopPlaybackMiniController.delegate`），
/// 不另起会话；首版不做「接下来播放」条（方案开放问题 5 默认）。
/// ±15s 沿用安卓画中画的无数字 rewind/forward 图标语义，数字进语义标签。
class DesktopPlaybackMiniPlayer extends StatefulWidget {
  const DesktopPlaybackMiniPlayer({
    super.key,
    required this.pinned,
    required this.onTogglePinned,
    required this.onRestore,
  });

  final bool pinned;
  final Future<void> Function() onTogglePinned;
  final Future<void> Function() onRestore;

  @override
  State<DesktopPlaybackMiniPlayer> createState() =>
      _DesktopPlaybackMiniPlayerState();
}

class _DesktopPlaybackMiniPlayerState extends State<DesktopPlaybackMiniPlayer> {
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // 外层跟随控制面身份重建（含 Esc/空格快捷键绑定），内层跟随播放状态。
    return ListenableBuilder(
      listenable: DesktopPlaybackMiniController.delegateRevision,
      builder: (context, _) {
        final delegate = DesktopPlaybackMiniController.delegate;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                unawaited(widget.onRestore()),
            if (delegate != null)
              const SingleActivator(LogicalKeyboardKey.space): () =>
                  unawaited(delegate.miniTogglePlay()),
          },
          child: Focus(
            autofocus: true,
            child: ColoredBox(
              color: colors.backgroundBase,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: DesktopFloatingPanel(
                  child: ListenableBuilder(
                    listenable:
                        delegate?.miniChanges ?? Listenable.merge(const []),
                    builder: (context, _) {
                      final current = DesktopPlaybackMiniController.delegate;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            _dragHandle(colors),
                            Expanded(child: _titleArea(current, colors)),
                            if (current != null) ...[
                              _button(
                                'desktop-mini-previous',
                                Icons.skip_previous_rounded,
                                '上一集',
                                current.miniCanPrevious
                                    ? () => unawaited(current.miniPrevious())
                                    : null,
                              ),
                              _button(
                                'desktop-mini-seek-back',
                                Icons.replay_rounded,
                                '后退 15 秒',
                                current.miniCanSeek
                                    ? () => unawaited(
                                        current.miniSeekBy(
                                          const Duration(seconds: -15),
                                        ),
                                      )
                                    : null,
                              ),
                              _button(
                                'desktop-mini-play-pause',
                                current.miniIsPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                current.miniIsPlaying ? '暂停' : '继续',
                                () => unawaited(current.miniTogglePlay()),
                                primary: true,
                              ),
                              _button(
                                'desktop-mini-seek-forward',
                                Icons.forward_rounded,
                                '前进 15 秒',
                                current.miniCanSeek
                                    ? () => unawaited(
                                        current.miniSeekBy(
                                          const Duration(seconds: 15),
                                        ),
                                      )
                                    : null,
                              ),
                              _button(
                                'desktop-mini-next',
                                Icons.skip_next_rounded,
                                '下一集',
                                current.miniCanNext
                                    ? () => unawaited(current.miniNext())
                                    : null,
                              ),
                            ],
                            _button(
                              'desktop-mini-pin',
                              widget.pinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              widget.pinned ? '取消置顶' : '置顶迷你窗',
                              () => unawaited(widget.onTogglePinned()),
                              primary: widget.pinned,
                            ),
                            _button(
                              'desktop-mini-restore',
                              Icons.open_in_full_rounded,
                              '还原播放页',
                              () => unawaited(widget.onRestore()),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dragHandle(AppThemeColors colors) {
    return Semantics(
      label: '拖动迷你窗',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => windowManager.startDragging(),
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
    );
  }

  Widget _titleArea(
    DesktopPlaybackMiniDelegate? delegate,
    AppThemeColors colors,
  ) {
    final title = delegate?.miniDisplayTitle ?? '';
    // 集名同时是拖拽热区：与外部播放器迷你条一致。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _button(
    String key,
    IconData icon,
    String label,
    VoidCallback? action, {
    bool primary = false,
  }) {
    final colors = context.appColors;
    return IconButton(
      key: ValueKey(key),
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
