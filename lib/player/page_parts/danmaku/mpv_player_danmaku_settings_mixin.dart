part of mpv_player_page;

extension _MpvPlayerDanmakuSettingsMixin on _MpvPlayerPageState {
  static const List<String> _danmakuAiBackendOrder = <String>[
    'paddle',
  ];
  static const List<String> _danmakuAiPrecisionPresets = <String>[
    DanmakuAiPrecisionPreset.performance,
    DanmakuAiPrecisionPreset.balanced,
    DanmakuAiPrecisionPreset.quality,
  ];

  String _danmakuStatusLabel() => _danmakuController.statusLabel;

  String _danmakuSummaryText() => _danmakuController.summaryText;

  String _danmakuSourcePriorityLabel() {
    return _danmakuController.settings.preferLocalSource ? '本地优先' : '网络优先';
  }

  String _danmakuOpacityLabel() {
    final percent = (_danmakuController.settings.opacity * 100).round();
    return '$percent%';
  }

  String _danmakuDensityLabel() {
    final percent = (_danmakuController.settings.density * 100).round();
    return '$percent%';
  }

  String _danmakuFontScaleLabel() {
    final scale = _danmakuController.settings.fontScale;
    if (scale < 0.8) return '较小';
    if (scale < 0.95) return '偏小';
    if (scale <= 1.05) return '标准';
    if (scale < 1.2) return '偏大';
    return '较大';
  }

  String _danmakuAreaLabel() {
    final ratio = _nearestDanmakuAreaPreset(
      _danmakuController.settings.displayAreaRatio,
    );
    if (ratio <= 0.10) return '1/10屏';
    if (ratio <= 0.25) return '1/4屏';
    if (ratio <= 0.5) return '半屏';
    if (ratio <= 0.75) return '3/4屏';
    return '全屏';
  }

  String _danmakuSpeedLabel() {
    final speed = _danmakuController.settings.speed;
    if (speed <= 0.85) return '慢速';
    if (speed >= 1.55) return '极速';
    if (speed >= 1.25) return '较快';
    return '标准';
  }

  String _danmakuAiSampleIntervalLabel() {
    return '${_danmakuController.settings.aiSampleIntervalMs}ms';
  }

  String _danmakuAiPrecisionLabel() {
    return switch (_danmakuController.settings.aiPrecisionPreset) {
      DanmakuAiPrecisionPreset.performance => '低',
      DanmakuAiPrecisionPreset.quality => '高',
      _ => '标准',
    };
  }

  String _danmakuAiInputSizeLabel() {
    final settings = _danmakuController.settings;
    return '${settings.aiInputWidth}x${settings.aiInputHeight}';
  }

  Future<void> _updateDanmakuSettings(
    DanmakuSettings Function(DanmakuSettings current) transformer,
  ) async {
    final next = transformer(_danmakuController.settings);
    await _danmakuController.updateSettings(next);
    await _syncDanmakuDynamicOcclusionConfig();
    if (!mounted) return;
    _updatePlayerState(() {});
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
    _showStatusMessage(
      nextEnabled ? '弹幕已开启' : '弹幕已关闭',
      hideAfter: const Duration(milliseconds: 1400),
    );
  }

  Future<void> _openDanmakuSettings() {
    if (_playerUiLocked) return Future<void>.value();
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

  Future<void> _setDanmakuDensity(double value) {
    return _updateDanmakuSettings(
      (current) => current.copyWith(density: value.clamp(0.2, 1.0)),
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

  Future<void> _setDanmakuAiSampleInterval(int value) {
    final normalized = value.clamp(
      DanmakuSettings.minAiSampleIntervalMs,
      DanmakuSettings.maxAiSampleIntervalMs,
    );
    return _updateDanmakuSettings(
      (current) => current.copyWith(aiSampleIntervalMs: normalized),
    );
  }

  Future<void> _setDanmakuAiInputWidth(int value) {
    final normalized = value.clamp(
      DanmakuSettings.minAiInputWidth,
      DanmakuSettings.maxAiInputWidth,
    );
    return _updateDanmakuSettings(
      (current) => current.copyWith(aiInputWidth: normalized),
    );
  }

  Future<void> _setDanmakuAiPrecisionPreset(String value) {
    final normalized = _danmakuAiPrecisionPresets.contains(value)
        ? value
        : DanmakuAiPrecisionPreset.balanced;
    return _updateDanmakuSettings(
      (current) => current.copyWith(aiPrecisionPreset: normalized),
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

  Future<void> _syncDanmakuDynamicOcclusionConfig() async {
    if (!Platform.isAndroid || !_platformViewAttached) {
      return;
    }
    final settings = _danmakuController.settings;
    final enabled =
        settings.enabled &&
        settings.avoidCenterArea &&
        !widget.pictureInPictureActive;
    await _controller.setDanmakuOcclusionConfig(<String, Object?>{
      'enabled': enabled,
      'sampleIntervalMs': settings.aiSampleIntervalMs,
      'preferredBackendOrder': _danmakuAiBackendOrder,
      'inputWidth': settings.aiInputWidth,
      'inputHeight': settings.aiInputHeight,
      'sampleAreaRatio': settings.displayAreaRatio,
    });
  }
}
