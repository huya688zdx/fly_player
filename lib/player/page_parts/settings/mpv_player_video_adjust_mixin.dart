part of mpv_player_page;

const double _videoAdjustmentMin = -100;
const double _videoAdjustmentMax = 100;

extension _MpvPlayerVideoAdjustMixin on _MpvPlayerPageState {
  Widget _buildPlaybackSettingsMpvOverviewPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: 'MPV 播放器设置',
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: '当前方案',
            value: _mpvOverviewStatusLabel(),
            description: _mpvOverviewSummaryText(),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '快速模式',
            subtitle: '一键预设与高保真模式',
            trailingLabel: _mpvQuickModeSummaryLabel(),
            onTap: () => drawer.push(_playerSettingsMpvPresetPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '画面调节',
            subtitle: '即时调节、视频滤镜、HDR 与插帧',
            trailingLabel: _mpvCategorySummaryLabel(
              _mpvPictureRenderingCategory,
            ),
            onTap: () => drawer.push(_playerSettingsMpvPictureRenderingPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '音频调节',
            subtitle: '高保真、EQ、限幅、低音、人声与声道混合',
            trailingLabel: _mpvCategorySummaryLabel(
              _mpvAudioProcessingCategory,
            ),
            onTap: () => drawer.push(_playerSettingsMpvAudioProcessingPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '播放与缓存',
            subtitle: '同步模式、缓存策略与缓冲大小',
            trailingLabel: _mpvCategorySummaryLabel(_mpvPlaybackSyncCategory),
            onTap: () => drawer.push(_playerSettingsMpvPlaybackSyncPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '兼容与诊断',
            subtitle: '兼容模式与播放诊断信息',
            trailingLabel: _mpvCategorySummaryLabel(_mpvCompatibilityCategory),
            onTap: () => drawer.push(_playerSettingsMpvCompatibilityPageId),
          ),
        ],
      ),
    );
  }

  Widget _buildMpvQuickAdjustPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final localValues = Map<String, double>.from(_videoAdjustments);
    return StatefulBuilder(
      builder: (context, setLocalState) {
        Future<void> commitValue(String key, double value) async {
          final next = Map<String, double>.from(localValues);
          next[key] = value;
          await _applyVideoAdjustments(next, drawer: drawer);
        }

        Future<void> resetAll() async {
          setLocalState(() {
            localValues
              ..clear()
              ..addAll(_MpvPlayerPageState._defaultVideoAdjustments);
          });
          await _applyVideoAdjustments(localValues, drawer: drawer);
        }

        return PlayerNestedSheetScaffold(
          header: PlayerNestedSheetHeader(
            title: '即时调节',
            onBack: drawer.popPage,
            actions: <Widget>[
              TextButton.icon(
                onPressed: () => unawaited(resetAll()),
                icon: const Icon(
                  Icons.restart_alt_rounded,
                  color: Colors.white,
                ),
                label: const Text(
                  '\u91cd\u7f6e',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ],
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              PlaybackSettingsStatusCard(
                title: '鐢婚潰鍙傛暟',
                value: _videoAdjustmentStatusLabel(),
                description:
                    '这些参数直接对应 mpv 原生视频均衡项，适合播放中微调，不会像 HDR 或插帧那样频繁触发重载。',
              ),
              const SizedBox(height: 12),
              for (
                var index = 0;
                index < _videoAdjustmentDefinitions.length;
                index++
              ) ...[
                PlaybackSettingsSliderTile(
                  title: _videoAdjustmentDefinitions[index].title,
                  subtitle: _videoAdjustmentDefinitions[index].subtitle,
                  valueLabel: _videoAdjustmentValueLabel(
                    localValues[_videoAdjustmentDefinitions[index].key] ?? 0,
                  ),
                  value:
                      localValues[_videoAdjustmentDefinitions[index].key] ?? 0,
                  min: _videoAdjustmentMin,
                  max: _videoAdjustmentMax,
                  divisions: (_videoAdjustmentMax - _videoAdjustmentMin)
                      .round(),
                  minLabel: '-100',
                  maxLabel: '+100',
                  onChanged: (value) {
                    setLocalState(() {
                      localValues[_videoAdjustmentDefinitions[index].key] =
                          _normalizeVideoAdjustmentValue(value);
                    });
                  },
                  onChangeEnd: (value) {
                    unawaited(
                      commitValue(
                        _videoAdjustmentDefinitions[index].key,
                        _normalizeVideoAdjustmentValue(value),
                      ),
                    );
                  },
                ),
                if (index != _videoAdjustmentDefinitions.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }

  List<_VideoAdjustmentDefinition> get _videoAdjustmentDefinitions =>
      const <_VideoAdjustmentDefinition>[
        _VideoAdjustmentDefinition(
          key: _MpvPlayerPageState._videoAdjustBrightness,
          title: '浜害',
          subtitle: '鎻愪寒鏆楀満鎴栧帇鏆楄繃鏇濈敾闈紝閫傚悎蹇€熶慨姝ｆ暣浣撴槑鏆椼€?',
        ),
        _VideoAdjustmentDefinition(
          key: _MpvPlayerPageState._videoAdjustContrast,
          title: '瀵规瘮搴?',
                  subtitle: '拉开明暗层次，数值过高会让高光和阴影更硬。',
        ),
        _VideoAdjustmentDefinition(
          key: _MpvPlayerPageState._videoAdjustSaturation,
          title: '楗卞拰搴?',
          subtitle: '鎺у埗鏁翠綋鑹插僵娴撳害锛屽亸浣庢洿绱犻泤锛屽亸楂樻洿椴滆壋銆?',
        ),
        _VideoAdjustmentDefinition(
          key: _MpvPlayerPageState._videoAdjustGamma,
          title: 'Gamma',
                  subtitle: '偏向中间调修正，适合微调灰雾感和暗部层次。',
        ),
        _VideoAdjustmentDefinition(
          key: _MpvPlayerPageState._videoAdjustHue,
          title: '鑹茬浉',
                  subtitle: '整体色调偏移，建议小幅调整，用来修正偏色片源。',
        ),
      ];

  Future<void> _applyVideoAdjustments(
    Map<String, double> values, {
    PlayerNestedSheetController<void>? drawer,
  }) async {
    final normalized = _normalizeVideoAdjustments(values);
    _updatePlayerState(() => _videoAdjustments = normalized);
    drawer?.refresh();
    await _controller.setVideoAdjustments(normalized);
  }

  Map<String, double> _normalizeVideoAdjustments(Map<String, double> values) {
    final normalized = <String, double>{};
    for (final entry in _MpvPlayerPageState._defaultVideoAdjustments.entries) {
      normalized[entry.key] = _normalizeVideoAdjustmentValue(
        values[entry.key] ?? entry.value,
      );
    }
    return normalized;
  }

  double _normalizeVideoAdjustmentValue(double value) {
    return value.clamp(_videoAdjustmentMin, _videoAdjustmentMax).toDouble();
  }

  int _videoAdjustmentChangedCount() {
    var count = 0;
    for (final entry in _MpvPlayerPageState._defaultVideoAdjustments.entries) {
      final current = _videoAdjustments[entry.key] ?? entry.value;
      if (_normalizeVideoAdjustmentValue(current) != entry.value) {
        count += 1;
      }
    }
    return count;
  }

  String _videoAdjustmentSummaryLabel() {
    final changed = _videoAdjustmentChangedCount();
    if (changed == 0) return '榛樿';
    if (changed == 1) {
      for (final definition in _videoAdjustmentDefinitions) {
        final current =
            _videoAdjustments[definition.key] ??
            _MpvPlayerPageState._defaultVideoAdjustments[definition.key]!;
        if (_normalizeVideoAdjustmentValue(current) != 0) {
          return '${definition.title} ${_videoAdjustmentValueLabel(current)}';
        }
      }
    }
    return '$changed 椤?';
  }

  String _videoAdjustmentStatusLabel() {
    final changed = _videoAdjustmentChangedCount();
    if (changed == 0) return '榛樿';
    final labels = <String>[];
    for (final definition in _videoAdjustmentDefinitions) {
      final current =
          _videoAdjustments[definition.key] ??
          _MpvPlayerPageState._defaultVideoAdjustments[definition.key]!;
      if (_normalizeVideoAdjustmentValue(current) == 0) continue;
      labels.add('${definition.title} ${_videoAdjustmentValueLabel(current)}');
      if (labels.length == 2) break;
    }
    return labels.join(' / ');
  }

  String _videoAdjustmentSummaryText() {
    final changed = _videoAdjustmentChangedCount();
    if (changed == 0) {
    return '亮度、对比度、饱和度、Gamma 和色相都保持在默认值。';
    }
    final labels = <String>[];
    for (final definition in _videoAdjustmentDefinitions) {
      final current =
          _videoAdjustments[definition.key] ??
          _MpvPlayerPageState._defaultVideoAdjustments[definition.key]!;
      if (_normalizeVideoAdjustmentValue(current) == 0) continue;
      labels.add('${definition.title} ${_videoAdjustmentValueLabel(current)}');
      if (labels.length == 3) break;
    }
    return '当前书签数量: $changed 条，章节: ${labels.join(' / ')}';
  }

  String _videoAdjustmentValueLabel(double value) {
    final normalized = _normalizeVideoAdjustmentValue(value).round();
    if (normalized > 0) return '+$normalized';
    return '$normalized';
  }

  String _mpvOverviewStatusLabel() {
    if (_videoAdjustmentChangedCount() > 0) return '已自定义';
    final preset = _activeMpvPreset();
    if (preset != null) return preset.label;
    if (_mpvChangedSettingCount() == 0) return '默认';
    return '已自定义';
  }

  String _mpvQuickModeSummaryLabel() {
    if (_mpvSettingValue(_MpvPlayerPageState._mpvSettingAudioHighFidelity) == 'on') {
      return '高保真';
    }
    final preset = _activeMpvPreset();
    if (preset != null) return preset.label;
    if (_mpvChangedSettingCount() == 0 && _videoAdjustmentChangedCount() == 0) {
      return '默认';
    }
    return '快速模式';
  }

  String _mpvOverviewSummaryText() {
    final videoAdjusted = _videoAdjustmentChangedCount();
    final advancedAdjusted = _mpvChangedSettingCount();
    final preset = _activeMpvPreset();
    if (preset != null && videoAdjusted == 0) {
      return preset.description;
    }
    if (videoAdjusted == 0 && advancedAdjusted == 0) {
      return '当前使用默认 MPV 参数。';
    }
    if (videoAdjusted > 0 && advancedAdjusted == 0) {
      return _videoAdjustmentSummaryText();
    }
    final labels = <String>[];
    for (final definition in _videoAdjustmentDefinitions) {
      final current =
          _videoAdjustments[definition.key] ??
          _MpvPlayerPageState._defaultVideoAdjustments[definition.key]!;
      if (_normalizeVideoAdjustmentValue(current) == 0) continue;
      labels.add('${definition.title} ${_videoAdjustmentValueLabel(current)}');
      if (labels.length == 3) break;
    }
    for (final definition in _mpvChoiceDefinitions) {
      final current = _mpvSettingValue(definition.key);
      final fallback = _MpvPlayerPageState._defaultMpvSettings[definition.key];
      if (current == fallback) continue;
      labels.add(
        '${definition.shortTitle} ${_mpvSettingLabel(definition.key)}',
      );
      if (labels.length == 3) break;
    }
    final changed = videoAdjusted + advancedAdjusted;
    return '当前书签数量: $changed 条，章节: ${labels.join(' / ')}';
  }
}

class _VideoAdjustmentDefinition {
  final String key;
  final String title;
  final String subtitle;

  const _VideoAdjustmentDefinition({
    required this.key,
    required this.title,
    required this.subtitle,
  });
}
