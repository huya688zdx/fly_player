part of mpv_player_page;

extension _MpvPlayerDanmakuSettingsMixin on _MpvPlayerPageState {
  String _danmakuStatusLabel() => _danmakuController.statusLabel;

  String _danmakuSummaryText() => _danmakuController.summaryText;

  String _danmakuSourcePriorityLabel() {
    return _danmakuController.settings.preferLocalSource
        ? '本地优先'
        : '网络优先';
  }

  String _danmakuOpacityLabel() {
    final percent = (_danmakuController.settings.opacity * 100).round();
    return '$percent%';
  }

  String _danmakuFontScaleLabel() {
    final percent = (_danmakuController.settings.fontScale * 100).round();
    return '$percent%';
  }

  String _danmakuAreaLabel() {
    final percent =
        (_nearestDanmakuAreaPreset(
                  _danmakuController.settings.displayAreaRatio,
                ) *
                100)
            .round();
    return '$percent%';
  }

  String _danmakuSpeedLabel() {
    final speed = _danmakuController.settings.speed;
    if (speed <= 0.85) return '慢速';
    if (speed >= 1.55) return '极速';
    if (speed >= 1.25) return '较快';
    return '标准';
  }

  Future<void> _updateDanmakuSettings(
    DanmakuSettings Function(DanmakuSettings current) transformer,
  ) {
    final next = transformer(_danmakuController.settings);
    return _danmakuController.updateSettings(next).then((_) {
      if (!mounted) return;
      _updatePlayerState(() {});
    });
  }

  Future<void> _toggleDanmakuEnabled() async {
    final nextEnabled = !_danmakuEnabled;
    await _updateDanmakuSettings(
      (current) => current.copyWith(enabled: nextEnabled),
    );
    if (nextEnabled) {
      await _tryLoadPreferredDanmakuSource();
    }
    if (!mounted) return;
    _showTopTip(
      nextEnabled ? '弹幕已开启' : '弹幕已关闭',
      nextEnabled ? context.appColors.success : context.appColors.warning,
    );
  }

  Future<void> _openDanmakuSettings() {
    return _showPlaybackSettingsDrawer(
      initialPageId: _playerSettingsDanmakuPageId,
    );
  }

  double _nearestDanmakuAreaPreset(double value) {
    return _danmakuAreaPresets.reduce((best, candidate) {
      return (candidate - value).abs() < (best - value).abs()
          ? candidate
          : best;
    });
  }

  Future<void> _setDanmakuAreaPreset(double value) {
    return _updateDanmakuSettings(
      (current) => current.copyWith(displayAreaRatio: value),
    );
  }

  Future<void> _setDanmakuOpacity(double value) {
    return _updateDanmakuSettings(
      (current) => current.copyWith(opacity: value.clamp(0.2, 1.0)),
    );
  }

  Future<void> _setDanmakuFontScale(double value) {
    return _updateDanmakuSettings(
      (current) => current.copyWith(fontScale: value.clamp(0.6, 1.4)),
    );
  }

  Future<void> _setDanmakuSpeed(double value) {
    return _updateDanmakuSettings(
      (current) => current.copyWith(speed: value.clamp(0.7, 1.8)),
    );
  }

  Future<void> _setDanmakuSourcePriority({
    required bool preferLocalSource,
  }) async {
    await _updateDanmakuSettings(
      (current) => current.copyWith(preferLocalSource: preferLocalSource),
    );
    _activeDanmakuSourceKey = null;
    await _danmakuSavedSourceStore.setActiveSourceKey(
      mediaKey: _currentDanmakuMediaKey(),
      sourceKey: null,
    );
    await _tryLoadPreferredDanmakuSource();
    if (!mounted) return;
    _showTopTip(
      preferLocalSource ? '已切换为本地优先' : '已切换为网络优先',
      context.appColors.success,
    );
  }
}
