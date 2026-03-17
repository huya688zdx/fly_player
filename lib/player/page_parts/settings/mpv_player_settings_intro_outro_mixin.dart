part of mpv_player_page;

extension _MpvPlayerSettingsIntroOutroMixin on _MpvPlayerPageState {
  Widget _buildPlaybackSettingsIntroOutroPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '片头片尾设置',
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
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        PlaybackSettingsStatusCard(
          title: 'OP/ED 跳过',
          value: _introOutroSourceModeLabel(),
          description: _introOutroDisplaySummaryTextV3(),
        ),
        const SizedBox(height: 12),
        PlaybackSettingsChoiceTile(
          title: '关闭',
          subtitle: '不自动跳过片头片尾',
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
          title: '自动跳过官方片头片尾',
          subtitle: '使用飞牛官方片头片尾时长配置',
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
            title: '飞牛官方设置',
            subtitle: '设置官方片头片尾跳过时长',
            trailingLabel:
                '${_formatSecondsLabel(_officialIntroDurationSeconds)} / ${_formatSecondsLabel(_officialOutroDurationSeconds)}',
            onTap: () => drawer.push(_playerSettingsOfficialConfigPageId),
          ),
        ],
        const SizedBox(height: 10),
        PlaybackSettingsChoiceTile(
          title: '章节判断跳过',
          subtitle: '根据章节自动判断，或手动选择章节作为 OP/ED',
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
            title: '章节跳过设置',
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
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '自动跳过官方片头片尾',
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsMenuTile(
            title: '跳过片头',
            trailingLabel: _formatSecondsLabel(_officialIntroDurationSeconds),
            onTap: () => drawer.push(_playerSettingsOfficialOpeningPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '跳过片尾',
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
    final title = intro ? '片头时长' : '片尾时长';
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
            description: intro ? '设置官方片头跳过时长' : '设置官方片尾跳过时长',
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '当前播放时间',
            subtitle: _formatSecondsLabel(currentSeconds),
            trailingLabel: intro ? '设为片头' : '设为片尾',
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
            title: '自定义',
            subtitle: '距离片头/片尾多少秒时开始跳过',
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
            title: '\u91cd\u7f6e',
            subtitle: '\u6062\u590d\u4e3a 0 \u79d2',
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
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '章节判断跳过',
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsChoiceTile(
            title: '自动判断',
            subtitle: '根据章节位置和短章节时长自动识别 OP/ED',
            selected:
                _chapterSkipMode == _MpvPlayerPageState._chapterSkipModeAuto,
            onTap: () {
              _setChapterSkipMode(_MpvPlayerPageState._chapterSkipModeAuto);
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsChoiceTile(
            title: '手动选择章节',
            subtitle: '手动指定章节作为片头片尾',
            selected:
                _chapterSkipMode == _MpvPlayerPageState._chapterSkipModeManual,
            onTap: () {
              _setChapterSkipMode(_MpvPlayerPageState._chapterSkipModeManual);
              drawer.refresh();
            },
          ),
          if (_chapterSkipMode == _MpvPlayerPageState._chapterSkipModeAuto) ...[
            const SizedBox(height: 16),
            const PlaybackSettingsSectionLabel(label: '自动判断范围'),
            const SizedBox(height: 10),
            PlaybackSettingsStepperTile(
              title: '片头最大章节时长',
              subtitle: '前段短章节小于该时长时，优先判定为片头',
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
              title: '片尾最大章节时长',
              subtitle: '尾段短章节小于该时长时，优先判定为片尾',
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
              title: '片头章节',
              subtitle: '手动指定片头章节',
              trailingLabel: _chapterSelectionLabel(
                chapters: _chapters,
                chapterIndex: _introChapterIndex,
              ),
              onTap: () => drawer.push(_playerSettingsIntroChapterPageId),
            ),
            const SizedBox(height: 12),
            PlaybackSettingsMenuTile(
              title: '片尾章节',
              subtitle: '手动指定片尾章节',
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
    if (chapterIndex == null) return '未设置';
    for (final item in chapters) {
      if (item.index != chapterIndex) continue;
      final title = item.title.trim();
      return title.isNotEmpty ? title : '绗?${item.index + 1} 绔?';
    }
    return '绗?${chapterIndex + 1} 绔?';
  }

  String _formatSecondsLabel(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
  }

  String _introOutroSourceModeLabel() {
    switch (_introOutroSourceMode) {
      case _MpvPlayerPageState._introOutroSourceModeOfficial:
        return '自动跳过官方片头片尾';
      case _MpvPlayerPageState._introOutroSourceModeChapter:
      return '章节判断';
      default:
        return '宸插叧闂?';
    }
  }

  String _chapterSkipModeLabel() {
    return _chapterSkipMode == _MpvPlayerPageState._chapterSkipModeManual
          ? '手动选择'
          : '自动判断';
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
    return '片头：$introLabel，片尾：$outroLabel';
    }
    final introLabel = _inferredIntroSkip?.label ?? '未识别';
    final outroLabel = _inferredOutroSkip?.label ?? '未识别';
    return '自动判断结果，片头：$introLabel，片尾：$outroLabel';
  }

  String _introOutroDisplayStatusLabelV3() {
    return _introOutroSourceModeLabel();
  }

  String _introOutroDisplaySummaryTextV3() {
    if (_introOutroSourceMode == _MpvPlayerPageState._introOutroSourceModeOff) {
    return '关闭后不会自动跳过片头片尾';
    }
    if (_introOutroSourceMode ==
        _MpvPlayerPageState._introOutroSourceModeOfficial) {
    return '官方片头 ${_formatSecondsLabel(_officialIntroDurationSeconds)}，片尾 ${_formatSecondsLabel(_officialOutroDurationSeconds)}';
    }
    return _chapterSkipModeSummaryText();
  }
}
