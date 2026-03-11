part of 'mpv_player_page.dart';

const String _playerSettingsMainPageId = 'player_settings_main';
const String _playerSettingsAdvancedPageId = 'player_settings_advanced';
const String _playerSettingsIntroOutroPageId = 'player_settings_intro_outro';
const String _playerSettingsVideoInfoPageId = 'player_settings_video_info';
const String _playerSettingsDecoderPageId = 'player_settings_decoder';
const String _playerSettingsIntroChapterPageId =
    'player_settings_intro_chapter';
const String _playerSettingsOutroChapterPageId =
    'player_settings_outro_chapter';
const String _playerSettingsOfficialConfigPageId =
    'player_settings_intro_outro_official';
const String _playerSettingsOfficialOpeningPageId =
    'player_settings_intro_outro_official_opening';
const String _playerSettingsOfficialEndingPageId =
    'player_settings_intro_outro_official_ending';
const String _playerSettingsChapterConfigPageId =
    'player_settings_intro_outro_chapter';

extension _MpvPlayerSettingsDrawerMixin on _MpvPlayerPageState {
  Future<void> _showPlaybackSettingsDrawer() async {
    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }

    if (!mounted) return;
    try {
      await PlayerNestedSheet.show<void>(
        context,
        initialPageId: _playerSettingsMainPageId,
        barrierLabel: 'player settings drawer',
        pages: <PlayerNestedSheetPage<void>>[
          PlayerNestedSheetPage<void>(
            id: _playerSettingsMainPageId,
            builder: _buildPlaybackSettingsMainPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsAdvancedPageId,
            builder: _buildPlaybackSettingsAdvancedPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsDecoderPageId,
            builder: _buildPlaybackSettingsDecoderPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsIntroOutroPageId,
            builder: _buildPlaybackSettingsIntroOutroPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsOfficialConfigPageId,
            builder: _buildPlaybackSettingsOfficialConfigPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsOfficialOpeningPageId,
            builder: (context, drawer) => _buildPlaybackSettingsOfficialTimePage(
              drawer,
              intro: true,
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsOfficialEndingPageId,
            builder: (context, drawer) => _buildPlaybackSettingsOfficialTimePage(
              drawer,
              intro: false,
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsChapterConfigPageId,
            builder: _buildPlaybackSettingsChapterConfigPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsIntroChapterPageId,
            builder: (context, drawer) => _buildPlaybackSettingsChapterPage(
              drawer,
              title: '选择片头章节',
              selectedIndex: _introChapterIndex,
              onSelected: (index) {
                _setIntroOutroChapter(intro: true, chapterIndex: index);
                drawer.popPage();
              },
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsOutroChapterPageId,
            builder: (context, drawer) => _buildPlaybackSettingsChapterPage(
              drawer,
              title: '选择片尾章节',
              selectedIndex: _outroChapterIndex,
              onSelected: (index) {
                _setIntroOutroChapter(intro: false, chapterIndex: index);
                drawer.popPage();
              },
            ),
          ),
          PlayerNestedSheetPage<void>(
            id: _playerSettingsVideoInfoPageId,
            builder: _buildPlaybackSettingsVideoInfoPage,
          ),
        ],
      );
    } finally {
      if (mounted) {
        if (restoreControls) {
          _showControls();
        }
      }
    }
  }

  Widget _buildPlaybackSettingsMainPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '设置',
        actions: <Widget>[
          PlaybackSettingsHeaderAction(
            icon: Icons.settings_rounded,
            label: '高级设置',
            onTap: () => drawer.push(_playerSettingsAdvancedPageId),
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsSwitchTile(
            title: '自动横屏',
            subtitle: _autoRotateEnabled ? '跟随系统方向自动切换' : '锁定当前播放方向',
            value: _autoRotateEnabled,
            onChanged: (value) {
              unawaited(_setAutoRotateEnabled(value));
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsAspectRatioTile(
            value: _displayAspectRatioMode,
            subtitle: '当前：${_displayAspectRatioLabel()}',
            onChanged: (value) {
              unawaited(_setDisplayAspectRatioMode(value));
              drawer.refresh();
            },
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '片头片尾设置',
            subtitle: _introOutroDisplaySummaryTextV3(),
            trailingLabel: _introOutroDisplayStatusLabelV3(),
            onTap: () => drawer.push(_playerSettingsIntroOutroPageId),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsAdvancedPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '高级设置', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsMenuTile(
            title: '解码方式',
            subtitle: '切换当前播放器使用的解码模式',
            trailingLabel: _decoderModeLabel(),
            onTap: () => drawer.push(_playerSettingsDecoderPageId),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsMenuTile(
            title: '显示视频详细信息',
            subtitle: '查看当前播放链路、渲染输出和片源信息',
            onTap: () => drawer.push(_playerSettingsVideoInfoPageId),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackSettingsDecoderPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '解码方式', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsChoiceTile(
            title: '硬解码',
            subtitle: '效率更高，功耗更低，优先推荐',
            selected: _decoderMode == _MpvPlayerPageState._decoderModeHardware,
            onTap: () => unawaited(
              _switchDecoderModeFromDrawer(
                _MpvPlayerPageState._decoderModeHardware,
                drawer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PlaybackSettingsChoiceTile(
            title: '软解码',
            subtitle: '兼容性更高，适合硬解异常时切换',
            selected: _decoderMode == _MpvPlayerPageState._decoderModeSoftware,
            onTap: () => unawaited(
              _switchDecoderModeFromDrawer(
                _MpvPlayerPageState._decoderModeSoftware,
                drawer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _switchDecoderModeFromDrawer(
    String mode,
    PlayerNestedSheetController<void> drawer,
  ) async {
    if (mode == _decoderMode) {
      drawer.close();
      return;
    }
    _updatePlayerState(() {
      _qualitySwitchLoading = true;
      _subtitleSwitchMessage = '正在切换为${_decoderModeLabel(mode)}，请稍等...';
    });
    drawer.close();
    try {
      await _setDecoderModePreference(mode);
      if (!mounted) return;
      _showControls();
    } finally {
      _updatePlayerState(() => _qualitySwitchLoading = false);
      _hideSubtitleSwitchMessage(delay: const Duration(milliseconds: 900));
    }
  }

  Widget _buildPlaybackSettingsIntroOutroPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '片头片尾设置', onBack: drawer.popPage),
      child: _buildIntroOutroMainList(drawer),
    );
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '片头片尾设置', onBack: drawer.popPage),
      child: PlaybackSettingsIntroOutroView(
        enabled: _introOutroEnabled,
        mode: _introOutroMode,
        introDurationSeconds: _introDurationSeconds,
        outroDurationSeconds: _outroDurationSeconds,
        chapterLoader: _controller.getChapters,
        summaryBuilder: (chapters) => _introOutroDisplaySummaryTextV3(),
        introChapterLabelBuilder: (chapters) => _chapterSelectionLabel(
          chapters: chapters,
          chapterIndex: _introChapterIndex,
        ),
        outroChapterLabelBuilder: (chapters) => _chapterSelectionLabel(
          chapters: chapters,
          chapterIndex: _outroChapterIndex,
        ),
        onEnabledChanged: (value) {
          _setIntroOutroEnabled(value);
          drawer.refresh();
        },
        onModeChanged: (value) {
          _setIntroOutroMode(value);
          drawer.refresh();
        },
        onPickIntroChapter: () =>
            drawer.push(_playerSettingsIntroChapterPageId),
        onPickOutroChapter: () =>
            drawer.push(_playerSettingsOutroChapterPageId),
        onAdjustIntroDuration: (deltaSeconds) {
          _adjustIntroOutroDuration(intro: true, deltaSeconds: deltaSeconds);
          drawer.refresh();
        },
        onAdjustOutroDuration: (deltaSeconds) {
          _adjustIntroOutroDuration(intro: false, deltaSeconds: deltaSeconds);
          drawer.refresh();
        },
      ),
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
            _setIntroOutroSourceMode(_MpvPlayerPageState._introOutroSourceModeOff);
            drawer.refresh();
          },
        ),
        const SizedBox(height: 10),
        PlaybackSettingsChoiceTile(
          title: '飞牛官方跳过',
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
      header: PlayerNestedSheetHeader(title: '飞牛官方跳过', onBack: drawer.popPage),
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
    final selectedSeconds =
        intro ? _officialIntroDurationSeconds : _officialOutroDurationSeconds;

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
            subtitle: '以 5 秒步进调整时长',
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
            title: '重置',
            subtitle: '恢复为 0 秒',
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
      header: PlayerNestedSheetHeader(title: '章节判断跳过', onBack: drawer.popPage),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PlaybackSettingsChoiceTile(
            title: '自动判断',
            subtitle: '根据章节位置和短章节长度自动识别 OP/ED',
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
          if (_chapterSkipMode ==
              _MpvPlayerPageState._chapterSkipModeAuto) ...[
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

  Widget _buildPlaybackSettingsVideoInfoPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '视频详细信息', onBack: drawer.popPage),
      child: FutureBuilder<Map<String, Object?>>(
        future: _controller.getPlaybackDiagnostics(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '读取播放数据失败: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          }
          final sections = _buildPlaybackDetailSections(
            snapshot.data ?? const <String, Object?>{},
          );
          if (sections.isEmpty) {
            return const Center(
              child: Text(
                '暂无可显示的播放信息',
                style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 14),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: sections.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                PlaybackDetailCard(section: sections[index]),
          );
        },
      ),
    );
  }

  List<PlaybackDetailSection> _buildPlaybackDetailSections(
    Map<String, Object?> diagnostics,
  ) {
    final playback = _diagnosticSection(diagnostics, 'playback');
    final source = _diagnosticSection(diagnostics, 'source');
    final output = _diagnosticSection(diagnostics, 'output');
    final display = _diagnosticSection(diagnostics, 'display');
    final mpv = _diagnosticSection(diagnostics, 'mpv');
    final sections = <PlaybackDetailSection>[
      PlaybackDetailSection(
        title: '播放信息',
        items: <PlaybackDetailItem>[
          PlaybackDetailItem('状态', _diagnosticString(playback['statusText'])),
          PlaybackDetailItem(
            '当前进度',
            _diagnosticDurationMs(playback['positionMs']),
          ),
          PlaybackDetailItem(
            '总时长',
            _diagnosticDurationMs(playback['durationMs']),
          ),
          PlaybackDetailItem(
            '播放速度',
            _diagnosticNumber(playback['playbackSpeed'], suffix: 'x'),
          ),
          PlaybackDetailItem('暂停', _diagnosticBool(playback['paused'])),
          PlaybackDetailItem('错误', _diagnosticString(playback['error'])),
        ],
      ),
      PlaybackDetailSection(
        title: '视频',
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            '编码',
            _diagnosticString(mpv['videoCodec'] ?? _currentVideoCodecName),
          ),
          PlaybackDetailItem(
            '分辨率',
            _joinDetailValues(<String>[
              _diagnosticResolution(mpv['videoParamsW'], mpv['videoParamsH']),
              _currentResolution.trim(),
            ]),
          ),
          PlaybackDetailItem('渲染输出', _diagnosticString(mpv['vo'])),
          PlaybackDetailItem(
            '解码方式',
            _decoderDetailLabelFromDiagnostics(output: output, mpv: mpv),
          ),
        ],
      ),
      PlaybackDetailSection(
        title: '音频',
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            '音轨',
            _currentAudioTrack()?.detailLabel.trim() ?? '',
          ),
          PlaybackDetailItem('编码', _diagnosticString(mpv['audioCodec'])),
          PlaybackDetailItem(
            '当前字幕',
            _currentSubtitleTrack()?.detailLabel.trim() ?? '关闭',
          ),
        ],
      ),
      PlaybackDetailSection(
        title: '输出与显示',
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            '色彩模式',
            _diagnosticString(output['windowColorMode']),
          ),
          PlaybackDetailItem(
            '设备信息',
            _diagnosticString(display['deviceProfile']),
          ),
        ],
      ),
      PlaybackDetailSection(
        title: '片源',
        items: <PlaybackDetailItem>[
          PlaybackDetailItem('标题', _currentTitle.trim()),
          PlaybackDetailItem(
            '媒体标识',
            _diagnosticString(source['mediaGuid'] ?? _currentMediaGuid),
          ),
          PlaybackDetailItem(
            '视频流',
            _diagnosticString(source['videoGuid'] ?? _currentVideoGuid),
          ),
          PlaybackDetailItem(
            '音频流',
            _diagnosticString(source['audioGuid'] ?? _currentAudioGuid),
          ),
          PlaybackDetailItem(
            '字幕流',
            _diagnosticString(source['subtitleGuid'] ?? _currentSubtitleGuid),
          ),
        ],
      ),
    ];
    return sections
        .map(
          (section) => PlaybackDetailSection(
            title: section.title,
            items: section.items
                .where((item) => item.value.trim().isNotEmpty)
                .toList(growable: false),
          ),
        )
        .where((section) => section.items.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, Object?> _diagnosticSection(
    Map<String, Object?> diagnostics,
    String key,
  ) {
    final raw = diagnostics[key];
    if (raw is Map<String, Object?>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, Object?>{};
  }

  String _diagnosticString(Object? value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty || text == '-' || text == 'null') return '';
    return text;
  }

  String _diagnosticBool(Object? value) {
    return value is bool ? (value ? '是' : '否') : _diagnosticString(value);
  }

  String _diagnosticNumber(Object? value, {String suffix = ''}) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty || text == '0' || text == '0.0') return '';
    return '$text$suffix';
  }

  String _diagnosticDurationMs(Object? value) {
    final raw = int.tryParse('${value ?? ''}');
    if (raw == null || raw <= 0) return '';
    return _formatDuration(Duration(milliseconds: raw));
  }

  String _diagnosticResolution(Object? width, Object? height) {
    final w = int.tryParse('${width ?? ''}') ?? 0;
    final h = int.tryParse('${height ?? ''}') ?? 0;
    if (w <= 0 || h <= 0) return '';
    return '${w}x$h';
  }

  String _joinDetailValues(List<String> values) {
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' / ');
  }

  String _decoderDetailLabelFromDiagnostics({
    required Map<String, Object?> output,
    required Map<String, Object?> mpv,
  }) {
    for (final candidate in <Object?>[
      output['preferredHwdecMode'],
      output['forcedHwdecMode'],
      output['activeHwdecMode'],
      mpv['hwdecCurrent'],
      _decoderMode == _MpvPlayerPageState._decoderModeSoftware ? 'no' : null,
    ]) {
      final label = _decoderDetailLabel(candidate);
      if (label.isNotEmpty) return label;
    }
    return '';
  }

  String _decoderDetailLabel(Object? value) {
    final normalized = _diagnosticString(value).toLowerCase();
    if (normalized.isEmpty) return '';
    if (normalized == 'no') return '软解码';
    if (normalized.contains('mediacodec')) return '硬解码';
    return normalized;
  }

  void _setIntroOutroEnabled(bool enabled) {
    if (_introOutroEnabled == enabled) return;
    _updatePlayerState(() {
      _introOutroEnabled = enabled;
      _introOutroMode = _MpvPlayerPageState._introOutroModeChapter;
      if (!enabled) {
        _activeChapterSkipPrompt = null;
        _skipPromptCountdownSeconds = 0;
      }
    });
    _recomputeChapterSkipSegments();
    unawaited(_persistIntroOutroPreferences(enabled: enabled));
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
        _activeChapterSkipPrompt = null;
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

  void _setIntroOutroMode(String mode) {
    _updatePlayerState(
      () => _introOutroMode = _MpvPlayerPageState._introOutroModeChapter,
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

  String _introOutroStatusLabel() {
    if (!_introOutroEnabled) return '已关闭';
    switch (_introOutroMode) {
      case _MpvPlayerPageState._introOutroModeChapter:
        return '章节模式';
      case _MpvPlayerPageState._introOutroModeManual:
        return '手动模式';
      default:
        return '自动模式';
    }
  }

  String _introOutroSummaryText({List<MpvChapterItem> chapters = const []}) {
    if (!_introOutroEnabled) return '关闭后不会自动跳过片头片尾';
    switch (_introOutroMode) {
      case _MpvPlayerPageState._introOutroModeChapter:
        return '片头：${_chapterSelectionLabel(chapters: chapters, chapterIndex: _introChapterIndex)}  片尾：${_chapterSelectionLabel(chapters: chapters, chapterIndex: _outroChapterIndex)}';
      case _MpvPlayerPageState._introOutroModeManual:
        return '片头 ${_formatSecondsLabel(_introDurationSeconds)}，片尾 ${_formatSecondsLabel(_outroDurationSeconds)}';
      default:
        return '优先使用章节，缺失时回退到手动时长';
    }
  }

  String _chapterSelectionLabel({
    required List<MpvChapterItem> chapters,
    required int? chapterIndex,
  }) {
    if (chapterIndex == null) return '未设置';
    for (final item in chapters) {
      if (item.index != chapterIndex) continue;
      final title = item.title.trim();
      return title.isNotEmpty ? title : '第 ${item.index + 1} 章';
    }
    return '第 ${chapterIndex + 1} 章';
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
        return '飞牛官方';
      case _MpvPlayerPageState._introOutroSourceModeChapter:
        return '章节判断';
      default:
        return '已关闭';
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

  String _introOutroDisplayStatusLabelV2() {
    if (!_introOutroEnabled) return '已关闭';
    return '章节判断';
  }

  String _introOutroDisplaySummaryTextV2() {
    if (!_introOutroEnabled) return '关闭后不会自动跳过片头片尾';
    final introLabel = _inferredIntroSkip?.label ?? '未识别';
    final outroLabel = _inferredOutroSkip?.label ?? '未识别';
    return '按章节短段自动判断，片头：$introLabel，片尾：$outroLabel';
  }

  String _introOutroDisplayStatusLabel() {
    if (!_introOutroEnabled) return '已关闭';
    return '自动跳过';
  }

  String _introOutroDisplaySummaryText() {
    if (!_introOutroEnabled) return '关闭后不会自动跳过片头片尾';
    return '已开启，片头 ${_formatSecondsLabel(_introDurationSeconds)}，片尾 ${_formatSecondsLabel(_outroDurationSeconds)}';
  }
}
