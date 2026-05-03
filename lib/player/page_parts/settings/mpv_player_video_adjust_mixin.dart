part of '../../mpv_player_page.dart';

const double _videoAdjustmentMin = -100;
const double _videoAdjustmentMax = 100;

extension _MpvPlayerVideoAdjustMixin on _MpvPlayerPageState {
  Widget _buildPlaybackSettingsMpvOverviewPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) => _buildPlaybackSettingsMpvHubPage(context, drawer);

  Widget _buildMpvQuickAdjustPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final localValues = Map<String, double>.from(_videoAdjustments);
    final l10n = AppLocalizations.of(context);
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
            title: l10n.mpvInstantAdjustTitle,
            onBack: drawer.popPage,
            actions: <Widget>[
              TextButton.icon(
                onPressed: () => unawaited(resetAll()),
                icon: const Icon(
                  Icons.restart_alt_rounded,
                  color: Colors.white,
                ),
                label: Text(
                  l10n.commonReset,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ],
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              PlaybackSettingsStatusCard(
                title: l10n.mpvVideoAdjustStatusTitle,
                value: _videoAdjustmentStatusLabel(),
                description: l10n.mpvVideoAdjustDrawerDescription,
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

  List<_VideoAdjustmentDefinition> get _videoAdjustmentDefinitions {
    final l10n = AppLocalizations.of(context);
    return <_VideoAdjustmentDefinition>[
      _videoAdjustmentDefinition(
        l10n,
        _MpvPlayerPageState._videoAdjustBrightness,
      ),
      _videoAdjustmentDefinition(
        l10n,
        _MpvPlayerPageState._videoAdjustContrast,
      ),
      _videoAdjustmentDefinition(
        l10n,
        _MpvPlayerPageState._videoAdjustSaturation,
      ),
      _videoAdjustmentDefinition(l10n, _MpvPlayerPageState._videoAdjustGamma),
      _videoAdjustmentDefinition(l10n, _MpvPlayerPageState._videoAdjustHue),
    ];
  }

  _VideoAdjustmentDefinition _videoAdjustmentDefinition(
    AppLocalizations l10n,
    String key,
  ) {
    return _VideoAdjustmentDefinition(
      key: key,
      title: MpvSettingsL10n.videoAdjustmentTitle(l10n, key),
      subtitle: MpvSettingsL10n.videoAdjustmentSubtitle(l10n, key),
    );
  }

  Future<void> _applyVideoAdjustments(
    Map<String, double> values, {
    PlayerNestedSheetController<void>? drawer,
  }) async {
    final normalized = _normalizeVideoAdjustments(values);
    await _mpvSettingsStore.saveVideoAdjustments(normalized);
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
    final l10n = AppLocalizations.of(context);
    final changed = _videoAdjustmentChangedCount();
    if (changed == 0) return MpvSettingsL10n.defaultLabel(l10n);
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
    return MpvSettingsL10n.changedCount(l10n, changed);
  }

  String _videoAdjustmentStatusLabel() {
    final l10n = AppLocalizations.of(context);
    final changed = _videoAdjustmentChangedCount();
    if (changed == 0) return MpvSettingsL10n.defaultLabel(l10n);
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
    final l10n = AppLocalizations.of(context);
    final changed = _videoAdjustmentChangedCount();
    if (changed == 0) {
      return l10n.mpvVideoAdjustAllDefaultSummary;
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
    return '${MpvSettingsL10n.changedCount(l10n, changed)}: ${labels.join(' / ')}';
  }

  String _videoAdjustmentValueLabel(double value) {
    final normalized = _normalizeVideoAdjustmentValue(value).round();
    if (normalized > 0) return '+$normalized';
    return '$normalized';
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
