part of '../../mpv_player_page.dart';

extension _MpvPlayerDanmakuSettingsMixin on _MpvPlayerPageState {
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

  String _danmakuThicknessLabel() {
    final thickness = _nearestDanmakuThicknessPreset(
      _danmakuController.settings.fontThickness,
    );
    if (thickness <= 0.8) return '较细';
    if (thickness >= 1.4) return '很粗';
    if (thickness >= 1.2) return '较粗';
    return '标准';
  }

  String _danmakuAreaLabel() {
    final ratio = _nearestDanmakuAreaPreset(
      _danmakuController.settings.displayAreaRatio,
    );
    if (ratio <= 0.25) return '1/4 屏';
    if (ratio <= 0.5) return '半屏';
    if (ratio <= 0.75) return '3/4 屏';
    return '全屏';
  }

  String _danmakuSpeedLabel() {
    // 无级变速：直接显示倍速（1.0× 为正常，<1 更慢，>1 更快）。
    final speed = clampDanmakuSpeed(_danmakuController.settings.speed);
    return '${speed.toStringAsFixed(speed >= 1.0 ? 1 : 2)}×';
  }

  String _danmakuFrameRateLabel() {
    final frameRate = _nearestDanmakuFrameRatePreset(
      _danmakuController.settings.targetFrameRateHz,
    );
    return '$frameRate FPS';
  }

  String _danmakuAiSampleIntervalLabel() {
    final intervalMs = _nearestDanmakuAiSampleIntervalPreset(
      _danmakuController.settings.aiSampleIntervalMs,
    ).round();
    return '${intervalMs}ms';
  }

  String _danmakuAiInputSizeLabel() {
    final inputWidth = _nearestDanmakuAiInputWidthPreset(
      _danmakuController.settings.aiInputWidth,
    ).round();
    final inputHeight = ((inputWidth * 9) / 16).round();
    final normalizedHeight = inputHeight.isEven ? inputHeight : inputHeight + 1;
    return '$inputWidth x $normalizedHeight';
  }

  String _danmakuOcclusionStatusTitle() {
    final state = _controller.danmakuOcclusionState.value;
    if (!state.enabled) {
      return '主体遮挡已关闭';
    }
    if (state.available) {
      return switch (state.occlusionMode.trim().toLowerCase()) {
        'mask' => '精细遮罩中',
        'bbox' => '人物框兜底中',
        _ => '主体遮挡已启用',
      };
    }
    return '主体遮挡暂不可用';
  }

  String _danmakuOcclusionStatusSubtitle() {
    final state = _controller.danmakuOcclusionState.value;
    if (!state.enabled) {
      return '关闭后会恢复普通弹幕显示。';
    }
    final backend = state.backend.trim().isEmpty ? 'disabled' : state.backend;
    if (state.available) {
      final modeLabel = switch (state.occlusionMode.trim().toLowerCase()) {
        'mask' => state.cacheHit ? '已复用精细遮罩缓存' : '正在使用实时精细遮罩',
        'bbox' => '正在使用人物框兜底',
        _ => '遮挡状态正常',
      };
      return '当前后端：$backend，$modeLabel。';
    }
    final reason = _danmakuOcclusionUnavailableLabel(state.unavailableReason);
    return '当前后端：$backend${reason == null ? '' : '，$reason'}';
  }

  String? _danmakuOcclusionUnavailableLabel(String? reason) {
    final normalized = reason?.trim().toLowerCase();
    switch (normalized) {
      case null:
      case '':
        return null;
      case 'capture_unsupported':
        return '当前视频输出后端不支持 AI 采样';
      case 'capture_budget_unsupported':
        return '当前链路在高刷新率下已禁用实时 AI 采样';
      default:
        return normalized;
    }
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

  Future<void> _setDanmakuUseNativeRenderer(bool value) async {
    await _updateDanmakuSettings(
      (current) => current.copyWith(useNativeRenderer: value),
    );
    if (!mounted) return;
    _showStatusMessage(
      value ? '已切换到原生弹幕渲染器，重新打开播放器后生效' : '已切换到 Flutter 弹幕渲染器，重新打开播放器后生效',
      hideAfter: const Duration(milliseconds: 2600),
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

  double _nearestDanmakuThicknessPreset(double value) {
    return _danmakuThicknessPresets.reduce((best, candidate) {
      return (candidate - value).abs() < (best - value).abs()
          ? candidate
          : best;
    });
  }

  int _nearestDanmakuFrameRatePreset(int value) {
    return danmakuFrameRatePresets.reduce((best, candidate) {
      return (candidate - value).abs() < (best - value).abs()
          ? candidate
          : best;
    });
  }

  double _nearestDanmakuAiSampleIntervalPreset(int value) {
    return _danmakuAiSampleIntervalPresets.reduce((best, candidate) {
      return (candidate - value).abs() < (best - value).abs()
          ? candidate
          : best;
    });
  }

  double _nearestDanmakuAiInputWidthPreset(int value) {
    return _danmakuAiInputWidthPresets.reduce((best, candidate) {
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

  Future<void> _setDanmakuFontThickness(double value) {
    return _updateDanmakuSettings(
      (current) => current.copyWith(fontThickness: value.clamp(0.8, 1.4)),
    );
  }

  Future<void> _setDanmakuSpeed(double value) {
    return _updateDanmakuSettings(
      (current) => current.copyWith(speed: clampDanmakuSpeed(value)),
    );
  }

  Future<void> _setDanmakuFrameRate(int value) {
    return _updateDanmakuSettings(
      (current) => current.copyWith(
        targetFrameRateHz: normalizeDanmakuFrameRateHz(value),
      ),
    );
  }

  Future<void> _setDanmakuAiSampleInterval(int value) {
    return _updateDanmakuSettings(
      (current) => current.copyWith(
        aiSampleIntervalMs: value.clamp(
          DanmakuSettings.minAiSampleIntervalMs,
          DanmakuSettings.maxAiSampleIntervalMs,
        ),
      ),
    );
  }

  Future<void> _setDanmakuAiInputWidth(int value) {
    return _updateDanmakuSettings(
      (current) => current.copyWith(
        aiInputWidth: value.clamp(
          DanmakuSettings.minAiInputWidth,
          DanmakuSettings.maxAiInputWidth,
        ),
      ),
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
    if (!_platformViewAttached) {
      return;
    }
    final settings = _danmakuController.settings;
    final configSignature = <Object?>[
      settings.enabled,
      settings.avoidCenterArea,
      settings.aiSampleIntervalMs,
      settings.aiInputWidth,
      settings.targetFrameRateHz,
      settings.displayAreaRatio.toStringAsFixed(3),
      resolveDanmakuCaptureAreaRatio(
        settings.displayAreaRatio,
      ).toStringAsFixed(3),
    ].join('|');
    if (configSignature == _lastDanmakuOcclusionConfigSignature) {
      return;
    }
    _lastDanmakuOcclusionConfigSignature = configSignature;
    await _controller.setDanmakuOcclusionConfig(<String, Object?>{
      'enabled': settings.enabled && settings.avoidCenterArea,
      'sampleIntervalMs': settings.aiSampleIntervalMs,
      'renderTargetFrameRateHz': settings.targetFrameRateHz,
      'preferredBackendOrder': const <String>['paddle'],
      'inputWidth': settings.aiInputWidth,
      'inputHeight': settings.aiInputHeight,
      'displayAreaRatio': settings.displayAreaRatio,
      'sampleAreaRatio': resolveDanmakuCaptureAreaRatio(
        settings.displayAreaRatio,
      ),
    });
  }
}
