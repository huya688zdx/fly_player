part of '../../mpv_player_page.dart';

extension _MpvPlayerSettingsIntroOutroMixin on _MpvPlayerPageState {
  Widget _buildPlaybackSettingsIntroOutroPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.playerIntroOutroSettingsTitle,
        onBack: drawer.popPage,
      ),
      child: _buildIntroOutroMainList(drawer),
    );
  }

  Widget _buildPlaybackSettingsChapterPage(
    PlayerNestedSheetController<void> drawer, {
    required String title,
    required int? selectedIndex,
    required ValueChanged<int?> onSelected,
  }) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: title, onBack: drawer.popPage),
      child: PlaybackSettingsChapterPicker(
        loader: _controller.getChapters,
        selectedIndex: selectedIndex,
        onSelected: onSelected,
      ),
    );
  }

  Widget _buildIntroOutroMainList(PlayerNestedSheetController<void> drawer) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        PlaybackSettingsStatusCard(
          title: l10n.playerIntroOutroStatusTitle,
          value: _introOutroSourceModeLabel(),
          description: _introOutroDisplaySummaryTextV3(),
        ),
        const SizedBox(height: 12),
        PlaybackSettingsChoiceTile(
          title: l10n.playerIntroOutroOffTitle,
          subtitle: l10n.playerIntroOutroOffSubtitle,
          selected:
              _introOutroSourceMode ==
              _MpvPlayerPageState._introOutroSourceModeOff,
          onTap: () {
            _setIntroOutroSourceMode(
              _MpvPlayerPageState._introOutroSourceModeOff,
            );
            drawer.refresh();
          },
        ),
        const SizedBox(height: 10),
        PlaybackSettingsChoiceTile(
          title: l10n.playerIntroOutroOfficialTitle,
          subtitle: l10n.playerIntroOutroOfficialSubtitle,
          selected:
              _introOutroSourceMode ==
              _MpvPlayerPageState._introOutroSourceModeOfficial,
          onTap: () {
            _setIntroOutroSourceMode(
              _MpvPlayerPageState._introOutroSourceModeOfficial,
            );
            drawer.refresh();
          },
        ),
        if (_introOutroSourceMode ==
            _MpvPlayerPageState._introOutroSourceModeOfficial) ...[
          const SizedBox(height: 10),
          PlaybackSettingsMenuTile(
            title: l10n.playerIntroOutroOfficialSettingsTitle,
            subtitle: l10n.playerIntroOutroOfficialSettingsSubtitle,
            trailingLabel:
                '${_formatSecondsLabel(_officialIntroDurationSeconds)} / ${_formatSecondsLabel(_officialOutroDurationSeconds)}',
            onTap: () => drawer.push(_playerSettingsOfficialConfigPageId),
          ),
        ],
        const SizedBox(height: 10),
        PlaybackSettingsChoiceTile(
          title: l10n.playerIntroOutroChapterModeTitle,
          subtitle: l10n.playerIntroOutroChapterModeSubtitle,
          selected:
              _introOutroSourceMode ==
              _MpvPlayerPageState._introOutroSourceModeChapter,
          onTap: () {
            _setIntroOutroSourceMode(
              _MpvPlayerPageState._introOutroSourceModeChapter,
            );
            drawer.refresh();
          },
        ),
        if (_introOutroSourceMode ==
            _MpvPlayerPageState._introOutroSourceModeChapter) ...[
          const SizedBox(height: 10),
          PlaybackSettingsMenuTile(
            title: l10n.playerIntroOutroChapterSettingsTitle,
            subtitle: _chapterSkipModeSummaryText(),
            trailingLabel: _chapterSkipModeLabel(),
            onTap: () => drawer.push(_playerSettingsChapterConfigPageId),
          ),
        ],
      ],
    );
  }

  Widget _buildPlaybackSettingsOfficialConfigPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.playerIntroOutroOfficialTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsMenuTile(
            title: l10n.playerSkipIntroTitle,
            trailingLabel: _formatSecondsLabel(_officialIntroDurationSeconds),
            onTap: () => drawer.push(_playerSettingsOfficialOpeningPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.playerSkipOutroTitle,
            trailingLabel: _formatSecondsLabel(_officialOutroDurationSeconds),
            onTap: () => drawer.push(_playerSettingsOfficialEndingPageId),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsOfficialTimePage(
    PlayerNestedSheetController<void> drawer, {
    required bool intro,
  }) {
    final l10n = AppLocalizations.of(context);
    final title = intro
        ? l10n.playerIntroDurationTitle
        : l10n.playerOutroDurationTitle;
    final duration = _effectiveDuration();
    final currentPosition = _displayPosition(_controller.value.value);
    final currentSeconds = intro
        ? currentPosition.inSeconds.clamp(0, duration.inSeconds)
        : (duration - currentPosition).inSeconds.clamp(0, duration.inSeconds);
    final selectedSeconds = intro
        ? _officialIntroDurationSeconds
        : _officialOutroDurationSeconds;

    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: title, onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsStatusCard(
            title: title,
            value: _formatSecondsLabel(selectedSeconds),
            description: intro
                ? l10n.playerOfficialIntroDescription
                : l10n.playerOfficialOutroDescription,
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.playerCurrentPlaybackTime,
            subtitle: _formatSecondsLabel(currentSeconds),
            trailingLabel: intro
                ? l10n.playerSetAsIntro
                : l10n.playerSetAsOutro,
            onTap: () async {
              await _setOfficialIntroOutroDuration(
                intro: intro,
                seconds: currentSeconds,
              );
              if (mounted) {
                drawer.refresh();
              }
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsStepperTile(
            title: l10n.playerCustomDurationTitle,
            subtitle: l10n.playerCustomDurationSubtitle,
            valueLabel: _formatSecondsLabel(selectedSeconds),
            onDecrease: () async {
              await _setOfficialIntroOutroDuration(
                intro: intro,
                seconds: (selectedSeconds - 5).clamp(0, duration.inSeconds),
              );
              if (mounted) {
                drawer.refresh();
              }
            },
            onIncrease: () async {
              await _setOfficialIntroOutroDuration(
                intro: intro,
                seconds: (selectedSeconds + 5).clamp(0, duration.inSeconds),
              );
              if (mounted) {
                drawer.refresh();
              }
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: l10n.commonReset,
            subtitle: l10n.playerResetToZeroSeconds,
            onTap: () async {
              await _setOfficialIntroOutroDuration(intro: intro, seconds: 0);
              if (mounted) {
                drawer.refresh();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsChapterConfigPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.playerIntroOutroChapterModeTitle,
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsChoiceTile(
            title: l10n.playerIntroOutroAutoModeTitle,
            subtitle: l10n.playerIntroOutroAutoModeSubtitle,
            selected:
                _chapterSkipMode == _MpvPlayerPageState._chapterSkipModeAuto,
            onTap: () {
              _setChapterSkipMode(_MpvPlayerPageState._chapterSkipModeAuto);
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsChoiceTile(
            title: l10n.playerIntroOutroManualModeTitle,
            subtitle: l10n.playerIntroOutroManualModeSubtitle,
            selected:
                _chapterSkipMode == _MpvPlayerPageState._chapterSkipModeManual,
            onTap: () {
              _setChapterSkipMode(_MpvPlayerPageState._chapterSkipModeManual);
              drawer.refresh();
            },
          ),
          if (_chapterSkipMode == _MpvPlayerPageState._chapterSkipModeAuto) ...[
            const SizedBox(height: 16),
            PlaybackSettingsSectionLabel(
              label: l10n.playerIntroOutroAutoRangeLabel,
            ),
            const SizedBox(height: 10),
            PlaybackSettingsStepperTile(
              title: l10n.playerIntroMaxChapterDurationTitle,
              subtitle: l10n.playerIntroMaxChapterDurationSubtitle,
              valueLabel: _formatSecondsLabel(_introDurationSeconds),
              onDecrease: () {
                _adjustIntroOutroDuration(intro: true, deltaSeconds: -10);
                drawer.refresh();
              },
              onIncrease: () {
                _adjustIntroOutroDuration(intro: true, deltaSeconds: 10);
                drawer.refresh();
              },
            ),
            const SizedBox(height: 10),
            PlaybackSettingsStepperTile(
              title: l10n.playerOutroMaxChapterDurationTitle,
              subtitle: l10n.playerOutroMaxChapterDurationSubtitle,
              valueLabel: _formatSecondsLabel(_outroDurationSeconds),
              onDecrease: () {
                _adjustIntroOutroDuration(intro: false, deltaSeconds: -10);
                drawer.refresh();
              },
              onIncrease: () {
                _adjustIntroOutroDuration(intro: false, deltaSeconds: 10);
                drawer.refresh();
              },
            ),
          ],
          if (_chapterSkipMode ==
              _MpvPlayerPageState._chapterSkipModeManual) ...[
            const SizedBox(height: 16),
            PlaybackSettingsMenuTile(
              title: l10n.playerIntroChapterTitle,
              subtitle: l10n.playerIntroChapterSubtitle,
              trailingLabel: _chapterSelectionLabel(
                chapters: _chapters,
                chapterIndex: _introChapterIndex,
              ),
              onTap: () => drawer.push(_playerSettingsIntroChapterPageId),
            ),
            const SizedBox(height: 12),
            PlaybackSettingsMenuTile(
              title: l10n.playerOutroChapterTitle,
              subtitle: l10n.playerOutroChapterSubtitle,
              trailingLabel: _chapterSelectionLabel(
                chapters: _chapters,
                chapterIndex: _outroChapterIndex,
              ),
              onTap: () => drawer.push(_playerSettingsOutroChapterPageId),
            ),
          ],
        ],
      ),
    );
  }

  void _setIntroOutroSourceMode(String mode) {
    final normalized = switch (mode) {
      _MpvPlayerPageState._introOutroSourceModeOfficial =>
        _MpvPlayerPageState._introOutroSourceModeOfficial,
      _MpvPlayerPageState._introOutroSourceModeChapter =>
        _MpvPlayerPageState._introOutroSourceModeChapter,
      _ => _MpvPlayerPageState._introOutroSourceModeOff,
    };
    _updatePlayerState(() {
      _introOutroSourceMode = normalized;
      _introOutroEnabled =
          normalized != _MpvPlayerPageState._introOutroSourceModeOff;
      if (normalized == _MpvPlayerPageState._introOutroSourceModeOff) {
        _uiController.activeChapterSkipPrompt = null;
        _skipPromptCountdownSeconds = 0;
      }
    });
    unawaited(_persistIntroOutroPreferences());
    if (normalized == _MpvPlayerPageState._introOutroSourceModeOfficial) {
      unawaited(_syncIntroOutroConfigToServer(enabled: true));
    }
  }

  void _setChapterSkipMode(String mode) {
    final normalized = mode == _MpvPlayerPageState._chapterSkipModeManual
        ? _MpvPlayerPageState._chapterSkipModeManual
        : _MpvPlayerPageState._chapterSkipModeAuto;
    _updatePlayerState(() {
      _chapterSkipMode = normalized;
      _introOutroMode = normalized;
      if (normalized == _MpvPlayerPageState._chapterSkipModeAuto) {
        _introChapterIndex = _inferredIntroSkip?.chapterIndex;
        _outroChapterIndex = _inferredOutroSkip?.chapterIndex;
      }
    });
    _recomputeChapterSkipSegments();
    unawaited(_persistIntroOutroPreferences());
  }

  Future<void> _setOfficialIntroOutroDuration({
    required bool intro,
    required int seconds,
  }) async {
    final normalized = seconds.clamp(0, 60 * 60 * 3);
    _updatePlayerState(() {
      if (intro) {
        _officialIntroDurationSeconds = normalized;
      } else {
        _officialOutroDurationSeconds = normalized;
      }
    });
    await _syncIntroOutroConfigToServer(
      enabled:
          _introOutroSourceMode ==
          _MpvPlayerPageState._introOutroSourceModeOfficial,
    );
  }

  void _setIntroOutroChapter({
    required bool intro,
    required int? chapterIndex,
  }) {
    _updatePlayerState(() {
      if (intro) {
        _introChapterIndex = chapterIndex;
      } else {
        _outroChapterIndex = chapterIndex;
      }
    });
    _recomputeChapterSkipSegments();
    unawaited(_persistIntroOutroPreferences());
  }

  void _adjustIntroOutroDuration({
    required bool intro,
    required int deltaSeconds,
  }) {
    _updatePlayerState(() {
      if (intro) {
        _introDurationSeconds = (_introDurationSeconds + deltaSeconds).clamp(
          60,
          240,
        );
      } else {
        _outroDurationSeconds = (_outroDurationSeconds + deltaSeconds).clamp(
          60,
          240,
        );
      }
    });
    _recomputeChapterSkipSegments();
    unawaited(_persistIntroOutroPreferences());
  }

  String _chapterSelectionLabel({
    required List<MpvChapterItem> chapters,
    required int? chapterIndex,
  }) {
    final l10n = AppLocalizations.of(context);
    if (chapterIndex == null) return l10n.playerUnset;
    for (final item in chapters) {
      if (item.index != chapterIndex) continue;
      final title = item.title.trim();
      return title.isNotEmpty
          ? title
          : l10n.playerChapterNumber(item.index + 1);
    }
    return l10n.playerChapterNumber(chapterIndex + 1);
  }

  String _formatSecondsLabel(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
  }

  String _introOutroSourceModeLabel() {
    final l10n = AppLocalizations.of(context);
    switch (_introOutroSourceMode) {
      case _MpvPlayerPageState._introOutroSourceModeOfficial:
        return l10n.playerIntroOutroOfficialTitle;
      case _MpvPlayerPageState._introOutroSourceModeChapter:
        return l10n.playerIntroOutroSourceChapterLabel;
      default:
        return l10n.playerIntroOutroSourceOffLabel;
    }
  }

  String _chapterSkipModeLabel() {
    final l10n = AppLocalizations.of(context);
    return _chapterSkipMode == _MpvPlayerPageState._chapterSkipModeManual
        ? l10n.playerIntroOutroManualLabel
        : l10n.playerIntroOutroAutoLabel;
  }

  String _chapterSkipModeSummaryText() {
    if (_chapterSkipMode == _MpvPlayerPageState._chapterSkipModeManual) {
      final introLabel = _chapterSelectionLabel(
        chapters: _chapters,
        chapterIndex: _introChapterIndex,
      );
      final outroLabel = _chapterSelectionLabel(
        chapters: _chapters,
        chapterIndex: _outroChapterIndex,
      );
      return AppLocalizations.of(
        context,
      ).playerIntroOutroManualSummary(introLabel, outroLabel);
    }
    final l10n = AppLocalizations.of(context);
    final introLabel = _inferredIntroSkip?.label ?? l10n.playerUnrecognized;
    final outroLabel = _inferredOutroSkip?.label ?? l10n.playerUnrecognized;
    return l10n.playerIntroOutroAutoSummary(introLabel, outroLabel);
  }

  String _introOutroDisplayStatusLabelV3() {
    return _introOutroSourceModeLabel();
  }

  String _introOutroDisplaySummaryTextV3() {
    if (_introOutroSourceMode == _MpvPlayerPageState._introOutroSourceModeOff) {
      return AppLocalizations.of(context).playerIntroOutroOffSummary;
    }
    if (_introOutroSourceMode ==
        _MpvPlayerPageState._introOutroSourceModeOfficial) {
      return AppLocalizations.of(context).playerIntroOutroOfficialSummary(
        _formatSecondsLabel(_officialIntroDurationSeconds),
        _formatSecondsLabel(_officialOutroDurationSeconds),
      );
    }
    return _chapterSkipModeSummaryText();
  }
}
