import 'package:flutter/material.dart';

import '../../danmaku/models/danmaku_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/track_option_sheet.dart';
import '../desktop_hover_dropdown.dart';
import 'external_playback_host.dart';
import 'external_player_subtitles.dart';

/// 极简窗口的二次展开区；拖动只编辑草稿，确认后才重新加载字幕。
class ExternalPlaybackMiniSettings extends StatefulWidget {
  const ExternalPlaybackMiniSettings({super.key, required this.status});

  final ExternalPlaybackStatus status;

  @override
  State<ExternalPlaybackMiniSettings> createState() =>
      _ExternalPlaybackMiniSettingsState();
}

class _ExternalPlaybackMiniSettingsState
    extends State<ExternalPlaybackMiniSettings> {
  final _subtitleMenu = GlobalKey<DesktopHoverDropdownState>();
  late DanmakuSettings _draft;
  String? _subtitleGuid;
  bool _dirty = false;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _draft = widget.status.danmakuSettings;
    _subtitleGuid = widget.status.source.subtitleTrackGuid;
    _dirty = false;
  }

  @override
  void didUpdateWidget(covariant ExternalPlaybackMiniSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && !_saving) _reset();
  }

  void _edit(DanmakuSettings value) => setState(() {
    _draft = value;
    _dirty = true;
    _message = null;
  });

  Future<void> _apply() async {
    if (_saving || !_dirty || !widget.status.canControl) return;
    final status = widget.status;
    // 保留调节区之外的最新开关与显示区域，避免覆盖用户刚做的其他操作。
    final settings = status.danmakuSettings.copyWith(
      fontScale: _draft.fontScale,
      opacity: _draft.opacity,
      density: _draft.density,
      speed: _draft.speed,
    );
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final applied = await ExternalPlaybackHost.applySettings(
        itemGuid: status.source.itemGuid,
        settings: settings,
        subtitleGuid: _subtitleGuid == status.source.subtitleTrackGuid
            ? null
            : _subtitleGuid,
      );
      if (!mounted) return;
      setState(() {
        if (applied) _dirty = false;
        _message = applied ? '已应用' : '未能应用，请检查当前字幕或重试';
      });
    } catch (_) {
      if (mounted) setState(() => _message = '应用失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final source = widget.status.source;
    final tracks = ExternalPlayerSubtitles.selectableTracks(source);
    final options = <String, String>{
      if (source.subtitleTrackGuid == null)
        'potplayer-default': '由 PotPlayer 选择',
      '': '关闭影片字幕',
      for (final track in tracks)
        track.guid:
            '${track.title.trim().isEmpty ? track.displayLabel : track.title.trim()}${track.detailLabel.isEmpty ? '' : ' · ${track.detailLabel}'}',
    };
    final selected = _subtitleGuid ?? 'potplayer-default';
    final canEdit = widget.status.canControl && !_saving;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 12, color: colors.borderSubtle),
          Text(
            '弹幕与字幕',
            style: TextStyle(
              fontSize: 12,
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          _slider(
            '字号',
            _draft.fontScale,
            .6,
            1.4,
            '${(_draft.fontScale * 100).round()}%',
            canEdit ? (v) => _edit(_draft.copyWith(fontScale: v)) : null,
          ),
          _slider(
            '不透明度',
            _draft.opacity,
            .2,
            1,
            '${(_draft.opacity * 100).round()}%',
            canEdit ? (v) => _edit(_draft.copyWith(opacity: v)) : null,
          ),
          _slider(
            '密度',
            _draft.density,
            .2,
            1,
            '${_draft.density.toStringAsFixed(1)}×',
            canEdit ? (v) => _edit(_draft.copyWith(density: v)) : null,
          ),
          _slider(
            '速度',
            _draft.speed,
            .5,
            2,
            '${_draft.speed.toStringAsFixed(1)}×',
            canEdit ? (v) => _edit(_draft.copyWith(speed: v)) : null,
          ),
          const SizedBox(height: 5),
          DesktopHoverDropdown(
            key: _subtitleMenu,
            activation: DesktopDropdownActivation.tap,
            spec: canEdit
                ? DesktopHoverDropdownSpec.single(
                    title: '影片字幕',
                    width: 316,
                    maxHeight: 240,
                    items: [
                      for (final entry in options.entries)
                        TrackOptionSheetItem(id: entry.key, title: entry.value),
                    ],
                    selectedId: selected,
                    onSelected: (id) {
                      _subtitleMenu.currentState?.hide();
                      setState(() {
                        _subtitleGuid = id == 'potplayer-default' ? null : id;
                        _dirty = true;
                        _message = null;
                      });
                    },
                  )
                : null,
            child: InkWell(
              onTap: canEdit
                  ? () => _subtitleMenu.currentState?.toggle()
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: colors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.subtitles_outlined,
                      size: 16,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        options[selected] ?? '内封字幕（PotPlayer 管理）',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '内封 / 位图字幕请在 PotPlayer 中切换',
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _message ?? (_dirty ? '调节后点击应用' : '设置与当前播放同步'),
                  maxLines: 2,
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
              ),
              TextButton(
                onPressed: canEdit && _dirty
                    ? () => setState(() {
                        _reset();
                        _message = null;
                      })
                    : null,
                child: const Text('还原', style: TextStyle(fontSize: 11)),
              ),
              FilledButton(
                onPressed: canEdit && _dirty ? _apply : null,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text(
                  _saving ? '应用中…' : '应用',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    String display,
    ValueChanged<double>? onChanged,
  ) {
    final colors = context.appColors;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
