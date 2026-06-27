part of '../../mpv_player_page.dart';

extension _MpvPlayerDanmakuSettingsMixin on _MpvPlayerPageState {
  String _danmakuStatusLabel() => _danmakuController.statusLabel;

  String _danmakuSummaryText() => _danmakuController.summaryText;

  String _danmakuSourcePriorityLabel() {
    final l10n = AppLocalizations.of(context);
    return _danmakuController.settings.preferLocalSource
        ? l10n.danmakuLocalFirst
        : l10n.danmakuNetworkFirst;
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
    final l10n = AppLocalizations.of(context);
    if (scale < 0.8) return l10n.danmakuSizeSmall;
    if (scale < 0.95) return l10n.danmakuSizeSlightlySmall;
    if (scale <= 1.05) return l10n.danmakuSizeStandard;
    if (scale < 1.2) return l10n.danmakuSizeSlightlyLarge;
    return l10n.danmakuSizeLarge;
  }

  String _danmakuThicknessLabel() {
    final thickness = _nearestDanmakuThicknessPreset(
      _danmakuController.settings.fontThickness,
    );
    final l10n = AppLocalizations.of(context);
    if (thickness <= 0.8) return l10n.danmakuWeightThin;
    if (thickness >= 1.4) return l10n.danmakuWeightVeryThick;
    if (thickness >= 1.2) return l10n.danmakuWeightThick;
    return l10n.danmakuSizeStandard;
  }

  String _danmakuAreaLabel() {
    final ratio = _nearestDanmakuAreaPreset(
      _danmakuController.settings.displayAreaRatio,
    );
    final l10n = AppLocalizations.of(context);
    if (ratio <= 0.25) return l10n.danmakuAreaQuarter;
    if (ratio <= 0.5) return l10n.danmakuAreaHalf;
    if (ratio <= 0.75) return l10n.danmakuAreaThreeQuarter;
    return l10n.danmakuAreaFull;
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
    final l10n = AppLocalizations.of(context);
    if (!state.enabled) {
      return l10n.danmakuOcclusionDisabledTitle;
    }
    if (state.available) {
      return switch (state.occlusionMode.trim().toLowerCase()) {
        'mask' => l10n.danmakuOcclusionMaskTitle,
        'bbox' => l10n.danmakuOcclusionBboxTitle,
        _ => l10n.danmakuOcclusionEnabledTitle,
      };
    }
    return l10n.danmakuOcclusionUnavailableTitle;
  }

  String _danmakuOcclusionStatusSubtitle() {
    final state = _controller.danmakuOcclusionState.value;
    final l10n = AppLocalizations.of(context);
    if (!state.enabled) {
      return l10n.danmakuOcclusionDisabledSubtitle;
    }
    final backend = state.backend.trim().isEmpty ? 'disabled' : state.backend;
    if (state.available) {
      final modeLabel = switch (state.occlusionMode.trim().toLowerCase()) {
        'mask' =>
          state.cacheHit
              ? l10n.danmakuOcclusionMaskCached
              : l10n.danmakuOcclusionMaskRealtime,
        'bbox' => l10n.danmakuOcclusionBboxFallback,
        _ => l10n.danmakuOcclusionNormal,
      };
      return l10n.danmakuOcclusionBackendStatus(backend, modeLabel);
    }
    final reason = _danmakuOcclusionUnavailableLabel(state.unavailableReason);
    return reason == null
        ? l10n.danmakuOcclusionBackendOnly(backend)
        : l10n.danmakuOcclusionBackendWithReason(backend, reason);
  }

  String? _danmakuOcclusionUnavailableLabel(String? reason) {
    final normalized = reason?.trim().toLowerCase();
    switch (normalized) {
      case null:
      case '':
        return null;
      case 'capture_unsupported':
        return AppLocalizations.of(context).danmakuOcclusionCaptureUnsupported;
      case 'capture_budget_unsupported':
        return AppLocalizations.of(
          context,
        ).danmakuOcclusionCaptureBudgetUnsupported;
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
      nextEnabled
          ? AppLocalizations.of(context).danmakuEnabled
          : AppLocalizations.of(context).danmakuDisabled,
      hideAfter: const Duration(milliseconds: 1400),
    );
  }

  Future<void> _setDanmakuUseNativeRenderer(bool value) async {
    await _updateDanmakuSettings(
      (current) => current.copyWith(useNativeRenderer: value),
    );
    if (!mounted) return;
    _showStatusMessage(
      value
          ? AppLocalizations.of(context).danmakuSwitchedNativeRenderer
          : AppLocalizations.of(context).danmakuSwitchedFlutterRenderer,
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
      preferLocalSource
          ? AppLocalizations.of(context).danmakuSwitchedLocalFirst
          : AppLocalizations.of(context).danmakuSwitchedNetworkFirst,
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
