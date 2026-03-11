part of 'mpv_player_page.dart';

const String _subtitleMainPageId = 'subtitle_main';
const String _subtitleAdjustPageId = 'subtitle_adjust';
const String _subtitleAddPageId = 'subtitle_add';
const String _subtitleSearchPageId = 'subtitle_search';
const String _subtitleLanguagePageId = 'subtitle_language';

const double _subtitleScaleMin = 0.8;
const double _subtitleScaleMax = 2.0;

extension _MpvPlayerSubtitleDrawerMixin on _MpvPlayerPageState {
  Future<void> _showSubtitleDrawer() async {
    final nasProvider = context.read<NasProvider>();
    _deferredSubtitleSelectionTimer?.cancel();
    _overlayState.cancelAutoHide();
    final restoreControls = _controlsVisible;
    if (restoreControls) {
      _hideControlsImmediately();
    }
    try {
      final languageMap = await FeiniuApi(
        nasProvider,
      ).getTagIso6392Map(lan: 'zh-CN');
      if (languageMap.isNotEmpty) {
        MediaLanguageMapper.mergeLanguageMap(languageMap);
      }
    } catch (_) {}

    if (!mounted) return;
    try {
      await PlayerNestedSheet.show<void>(
        context,
        initialPageId: _subtitleMainPageId,
        barrierLabel: 'subtitle drawer',
        pages: <PlayerNestedSheetPage<void>>[
          PlayerNestedSheetPage<void>(
            id: _subtitleMainPageId,
            builder: _buildSubtitleMainPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _subtitleAdjustPageId,
            builder: _buildSubtitleAdjustPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _subtitleAddPageId,
            builder: _buildSubtitleAddPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _subtitleSearchPageId,
            builder: _buildSubtitleSearchPage,
          ),
          PlayerNestedSheetPage<void>(
            id: _subtitleLanguagePageId,
            builder: _buildSubtitleLanguagePage,
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

  Widget _buildSubtitleMainPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final items = <_SubtitleDrawerTileData>[
      _SubtitleDrawerTileData(
        title: '关闭',
        selected: (_currentSubtitleGuid ?? '').trim().isEmpty,
        onTap: () => unawaited(_selectSubtitleFromDrawer('', drawer)),
      ),
      ..._subtitleTracks.map(
        (track) => _SubtitleDrawerTileData(
          title: _subtitleTitle(track),
          subtitle: _subtitleSubtitle(track),
          trailingDetail: _subtitleStreamTitle(track),
          deleting: track.guid == _subtitleDeletingGuid,
          onDelete: _subtitleCanDelete(track)
              ? () => unawaited(_deleteSubtitleFromDrawer(track, drawer))
              : null,
          selected: track.guid == (_currentSubtitleGuid ?? '').trim(),
          onTap: () => unawaited(_selectSubtitleFromDrawer(track.guid, drawer)),
        ),
      ),
    ];

    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '字幕',
        actions: <Widget>[
          _SubtitleHeaderActionButton(
            icon: Icons.settings_rounded,
            label: '调整',
            onTap: () => drawer.push(_subtitleAdjustPageId),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '字幕列表',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _SubtitlePrimaryButton(
                icon: Icons.add_rounded,
                label: '字幕',
                onTap: () => drawer.push(_subtitleAddPageId),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 2),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return _SubtitleOptionTile(
                  title: item.title,
                  subtitle: item.subtitle,
                  trailingDetail: item.trailingDetail,
                  deleting: item.deleting,
                  onDelete: item.onDelete,
                  selected: item.selected,
                  onTap: item.onTap,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitleAddPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '选择字幕添加方式',
        onBack: drawer.popPage,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _SubtitleMenuTile(
            title: '搜索下载字幕',
            onTap: () {
              drawer.push(_subtitleSearchPageId);
              unawaited(_loadRemoteSubtitleSearch(drawer));
            },
          ),
          const SizedBox(height: 12),
          _SubtitleMenuTile(
            title: '添加本地字幕',
            onTap: () => unawaited(_pickAndAttachLocalSubtitle(drawer)),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitleSearchPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final loading = _subtitleSearchLoadingLanguage != null;
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '搜索下载字幕', onBack: drawer.popPage),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _currentTitle.trim().isEmpty ? '当前视频' : _currentTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _SubtitlePillButton(
                label: _subtitleSearchLanguageLabel(_subtitleSearchLanguage),
                onTap: () => drawer.push(_subtitleLanguagePageId),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '按相关度排序：',
            style: TextStyle(
              color: Color(0xB3FFFFFF),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: loading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                : _subtitleSearchResults.isEmpty
                ? const Center(
                    child: Text(
                      '未找到可下载字幕',
                      style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 15),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _subtitleSearchResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _subtitleSearchResults[index];
                      return _SubtitleSearchResultTile(
                        title: item.filename,
                        meta:
                            '${item.source.toUpperCase()}  ${item.format.toUpperCase()}',
                        downloads: item.download,
                        loading: item.trimId == _subtitleDownloadTrimId,
                        onTap: () => unawaited(
                          _downloadRemoteSubtitle(item: item, drawer: drawer),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitleLanguagePage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final items = <Map<String, String>>[
      <String, String>{'label': '中文', 'value': 'zh-CN'},
      <String, String>{'label': '英文', 'value': 'en'},
    ];
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '选择语言', onBack: drawer.popPage),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = items[index];
          final value = item['value']!;
          return _SubtitleOptionTile(
            title: item['label']!,
            selected: value == _subtitleSearchLanguage,
            onTap: () =>
                unawaited(_changeSubtitleSearchLanguage(value, drawer)),
          );
        },
      ),
    );
  }

  Widget _buildSubtitleAdjustPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: '字幕调整',
        onBack: drawer.popPage,
        actions: [
          TextButton.icon(
            onPressed: () => unawaited(_resetSubtitleStyle(drawer)),
            icon: const Icon(Icons.restart_alt_rounded, color: Colors.white),
            label: const Text(
              '重置',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _SubtitleAdjustRow(
            label: '偏移',
            child: Row(
              children: [
                Expanded(
                  child: _SubtitleActionCapsule(
                    label: '延迟',
                    onTap: () => unawaited(
                      _setSubtitleDelaySeconds(
                        _subtitleDelaySeconds + 0.1,
                        drawer: drawer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SubtitleValueCapsule(
                    label: '${_subtitleDelaySeconds.toStringAsFixed(1)}秒',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SubtitleActionCapsule(
                    label: '加快',
                    onTap: () => unawaited(
                      _setSubtitleDelaySeconds(
                        _subtitleDelaySeconds - 0.1,
                        drawer: drawer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SubtitleAdjustRow(
            label: '位置',
            child: Row(
              children: [
                const Text(
                  '底部',
                  style: TextStyle(color: Color(0x8FFFFFFF), fontSize: 14),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white38,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white12,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      min: 0,
                      max: 1,
                      value: _subtitlePositionFactor.clamp(0.0, 1.0).toDouble(),
                      onChanged: (value) => unawaited(
                        _setSubtitlePositionFactor(value, drawer: drawer),
                      ),
                    ),
                  ),
                ),
                const Text(
                  '顶部',
                  style: TextStyle(color: Color(0x8FFFFFFF), fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SubtitleAdjustRow(
            label: '字号',
            child: Row(
              children: [
                const Text(
                  '默认',
                  style: TextStyle(color: Color(0x8FFFFFFF), fontSize: 14),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF2D87FF),
                      inactiveTrackColor: Colors.white38,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white12,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      min: 0,
                      max: 1,
                      value: _subtitleScaleFactor.clamp(0.0, 1.0).toDouble(),
                      onChanged: (value) => unawaited(
                        _setSubtitleScaleFactor(value, drawer: drawer),
                      ),
                    ),
                  ),
                ),
                const Text(
                  '最大',
                  style: TextStyle(color: Color(0x8FFFFFFF), fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectSubtitleFromDrawer(
    String guid,
    PlayerNestedSheetController<void> drawer,
  ) async {
    final normalized = guid.trim();
    if (normalized == (_currentSubtitleGuid ?? '').trim()) {
      drawer.close();
      return;
    }
    final selected = _findSubtitleTrack(normalized);
    if (_serverPlaybackManaged &&
        normalized.isNotEmpty &&
        !_subtitleHasDirectFile(selected)) {
      _showTransientMessage('当前字幕暂不支持切换');
      return;
    }
    _updatePlayerState(() {
      _qualitySwitchLoading = true;
      _currentSubtitleGuid = normalized;
      if (normalized.isEmpty) return;
      _subtitleFailureNoticeShownGuids.remove(normalized);
      _serverFallbackSubtitleGuids.remove(normalized);
    });
    _showSubtitleSwitchMessage(_subtitleDrawerSwitchMessageForTrack(selected));
    try {
      await _applySubtitleSelection();
      _showControls();
      if (mounted) {
        drawer.close();
      }
    } finally {
      if (mounted) {
        _updatePlayerState(() => _qualitySwitchLoading = false);
      }
      _hideSubtitleSwitchMessage(delay: const Duration(milliseconds: 900));
    }
  }

  Future<void> _loadRemoteSubtitleSearch(
    PlayerNestedSheetController<void> drawer,
  ) async {
    final mediaGuid = _subtitleSourceMediaGuid.trim().isNotEmpty
        ? _subtitleSourceMediaGuid.trim()
        : _currentMediaGuid;
    if (mediaGuid.isEmpty) {
      _showTransientMessage('当前视频缺少媒体标识');
      return;
    }
    if (_subtitleSearchLoadingLanguage == _subtitleSearchLanguage) return;
    _subtitleSearchLoadingLanguage = _subtitleSearchLanguage;
    drawer.refresh();
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final result = await api.searchRemoteSubtitles(
        mediaGuid: mediaGuid,
        language: _subtitleSearchLanguage,
      );
      if (!mounted) return;
      _subtitleSearchResults = result.subtitles;
    } catch (error) {
      if (mounted) {
        _subtitleSearchResults = const <RemoteSubtitleSearchItem>[];
        _showTransientMessage('搜索字幕失败: $error');
      }
    } finally {
      _subtitleSearchLoadingLanguage = null;
      if (mounted) {
        drawer.refresh();
      }
    }
  }

  Future<void> _changeSubtitleSearchLanguage(
    String language,
    PlayerNestedSheetController<void> drawer,
  ) async {
    if (_subtitleSearchLanguage == language) {
      drawer.popPage();
      return;
    }
    _subtitleSearchLanguage = language;
    drawer.popPage();
    drawer.refresh();
    await _loadRemoteSubtitleSearch(drawer);
  }

  Future<void> _downloadRemoteSubtitle({
    required RemoteSubtitleSearchItem item,
    required PlayerNestedSheetController<void> drawer,
  }) async {
    final mediaGuid = _subtitleSourceMediaGuid.trim().isNotEmpty
        ? _subtitleSourceMediaGuid.trim()
        : _currentMediaGuid;
    if (mediaGuid.isEmpty) {
      _showTransientMessage('当前视频缺少媒体标识');
      return;
    }
    _subtitleDownloadTrimId = item.trimId;
    drawer.refresh();
    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final result = await api.downloadRemoteSubtitle(
        mediaGuid: mediaGuid,
        trimId: item.trimId,
      );
      if (!mounted) return;
      final track = result.toTrack(fallbackMediaGuid: mediaGuid);
      _upsertSubtitleTrack(track, insertAtFront: true);
      await _selectSubtitleFromDrawer(track.guid, drawer);
    } catch (error) {
      if (mounted) {
        _showTransientMessage('下载字幕失败: $error');
      }
    } finally {
      _subtitleDownloadTrimId = null;
      if (mounted) {
        drawer.refresh();
      }
    }
  }

  Future<void> _pickAndAttachLocalSubtitle(
    PlayerNestedSheetController<void> drawer,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const <String>[
          'ass',
          'ssa',
          'srt',
          'vtt',
          'sub',
          'txt',
        ],
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final path = await _materializePickedSubtitle(file);
      if (!mounted || path == null || path.isEmpty) return;
      final guid = 'local:${DateTime.now().microsecondsSinceEpoch}';
      final format = _subtitleFormatFromFileName(file.name, path);
      final title = file.name.trim().isNotEmpty
          ? file.name.trim()
          : path.split(Platform.pathSeparator).last;
      _subtitleFileByGuid[guid] = path;
      _upsertSubtitleTrack(
        SubtitleTrackOption(
          mediaGuid: _subtitleSourceMediaGuid.trim().isNotEmpty
              ? _subtitleSourceMediaGuid.trim()
              : _currentMediaGuid,
          guid: guid,
          title: title,
          codecName: format,
          format: format,
          language: 'und',
          index: -1,
          isDefault: 0,
          forced: 0,
          isExternal: 1,
          extraFile: 1,
          isBitmap: 0,
        ),
        insertAtFront: true,
      );
      await _selectSubtitleFromDrawer(guid, drawer);
    } catch (error) {
      if (mounted) {
        _showTransientMessage('添加本地字幕失败: $error');
      }
    }
  }

  Future<String?> _materializePickedSubtitle(PlatformFile file) async {
    final rawPath = file.path?.trim() ?? '';
    if (rawPath.isNotEmpty) {
      final source = File(rawPath);
      if (source.existsSync()) {
        return source.path;
      }
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final extension = _subtitleFormatFromFileName(file.name, rawPath);
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'fly_player_local_sub_${DateTime.now().microsecondsSinceEpoch}.$extension';
    return _writeSubtitleBytesToTempFile(
      path: path,
      bytes: Uint8List.fromList(bytes),
    );
  }

  void _upsertSubtitleTrack(
    SubtitleTrackOption track, {
    bool insertAtFront = false,
  }) {
    _updatePlayerState(() {
      final next = List<SubtitleTrackOption>.from(_subtitleTracks)
        ..removeWhere((item) => item.guid == track.guid);
      if (insertAtFront) {
        next.insert(0, track);
      } else {
        next.add(track);
      }
      _subtitleTracks = next;
    });
  }

  Future<void> _deleteSubtitleFromDrawer(
    SubtitleTrackOption track,
    PlayerNestedSheetController<void> drawer,
  ) async {
    if (_subtitleDeletingGuid == track.guid) return;
    _subtitleDeletingGuid = track.guid;
    drawer.refresh();
    try {
      if (!track.guid.startsWith('local:')) {
        final api = FeiniuApi(context.read<NasProvider>());
        await api.deleteSubtitle(
          subtitleGuid: track.guid,
          mediaGuid: track.mediaGuid,
        );
      }

      final isCurrent = track.guid == (_currentSubtitleGuid ?? '').trim();
      _removeCachedSubtitleFile(track.guid);
      _serverFallbackSubtitleGuids.remove(track.guid);
      _subtitleFailureNoticeShownGuids.remove(track.guid);
      _updatePlayerState(() {
        _subtitleTracks = List<SubtitleTrackOption>.from(_subtitleTracks)
          ..removeWhere((item) => item.guid == track.guid);
        if (isCurrent) {
          _currentSubtitleGuid = '';
        }
      });
      if (isCurrent) {
        await _applySubtitleSelection();
      }
    } catch (error) {
      if (mounted) {
        _showTransientMessage('删除字幕失败: $error');
      }
    } finally {
      _subtitleDeletingGuid = null;
      if (mounted) {
        drawer.refresh();
      }
    }
  }

  void _removeCachedSubtitleFile(String guid) {
    final path = _subtitleFileByGuid.remove(guid);
    if (path == null || path.isEmpty) return;
    unawaited(_deleteTempFile(path));
  }

  bool _subtitleCanDelete(SubtitleTrackOption track) {
    return track.isExternal == 1;
  }

  Future<void> _setSubtitleDelaySeconds(
    double value, {
    required PlayerNestedSheetController<void> drawer,
  }) async {
    final normalized = value.clamp(-10.0, 10.0).toDouble();
    _subtitleDelaySeconds = double.parse(normalized.toStringAsFixed(1));
    drawer.refresh();
    await _controller.setSubtitleDelay(_subtitleDelaySeconds);
  }

  Future<void> _setSubtitlePositionFactor(
    double value, {
    required PlayerNestedSheetController<void> drawer,
  }) async {
    _subtitlePositionFactor = value.clamp(0.0, 1.0).toDouble();
    drawer.refresh();
    final mpvPosition = ((1 - _subtitlePositionFactor) * 100)
        .round()
        .clamp(0, 100)
        .toInt();
    await _controller.setSubtitlePosition(mpvPosition);
  }

  Future<void> _setSubtitleScaleFactor(
    double value, {
    required PlayerNestedSheetController<void> drawer,
  }) async {
    _subtitleScaleFactor = value.clamp(0.0, 1.0).toDouble();
    drawer.refresh();
    final scale =
        _subtitleScaleMin +
        ((_subtitleScaleMax - _subtitleScaleMin) * _subtitleScaleFactor);
    await _controller.setSubtitleScale(scale);
  }

  Future<void> _resetSubtitleStyle(
    PlayerNestedSheetController<void> drawer,
  ) async {
    _subtitleDelaySeconds = 0;
    _subtitlePositionFactor = 0;
    _subtitleScaleFactor =
        (1.0 - _subtitleScaleMin) / (_subtitleScaleMax - _subtitleScaleMin);
    drawer.refresh();
    await _controller.resetSubtitleStyle();
  }

  String _subtitleSearchLanguageLabel(String language) {
    switch (language) {
      case 'en':
        return '英文';
      case 'zh-CN':
      default:
        return '中文';
    }
  }

  String _subtitleFormatFromFileName(String fileName, String fallbackPath) {
    final source = fileName.trim().isNotEmpty ? fileName.trim() : fallbackPath;
    final dot = source.lastIndexOf('.');
    if (dot < 0 || dot == source.length - 1) return 'ass';
    return source.substring(dot + 1).toLowerCase();
  }

  String _subtitleStreamTitle(SubtitleTrackOption track) {
    final raw = track.title.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (raw.isEmpty) return '';
    final format = _subtitleSubtitle(track).trim().toUpperCase();
    if (raw.toUpperCase() == format) return '';
    return raw;
  }

  String _subtitleDrawerSwitchMessageForTrack(SubtitleTrackOption? track) {
    if (track == null) {
      return '正在关闭字幕...';
    }
    final title = _subtitleTitle(track);
    final format = (track.format.isNotEmpty ? track.format : track.codecName)
        .trim()
        .toLowerCase();
    final suffix = format.isEmpty ? '' : ' ($format)';
    return '正在切换到 $title$suffix 字幕...';
  }
}

class _SubtitleDrawerTileData {
  final String title;
  final String subtitle;
  final String trailingDetail;
  final bool deleting;
  final VoidCallback? onDelete;
  final bool selected;
  final VoidCallback onTap;

  const _SubtitleDrawerTileData({
    required this.title,
    this.subtitle = '',
    this.trailingDetail = '',
    this.deleting = false,
    this.onDelete,
    required this.selected,
    required this.onTap,
  });
}

class _SubtitleHeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SubtitleHeaderActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 19),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}

class _SubtitlePrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SubtitlePrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E2B56),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 3),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitlePillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SubtitlePillButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1F2B52),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleMenuTile extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _SubtitleMenuTile({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x332D87FF)),
            color: Colors.white.withValues(alpha: 0.03),
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtitleOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailingDetail;
  final bool deleting;
  final VoidCallback? onDelete;
  final bool selected;
  final VoidCallback onTap;

  const _SubtitleOptionTile({
    required this.title,
    this.subtitle = '',
    this.trailingDetail = '',
    this.deleting = false,
    this.onDelete,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? const Color(0x183C7FE0)
                : Colors.white.withValues(alpha: 0.03),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2D87FF)
                  : Colors.white.withValues(alpha: 0.08),
              width: selected ? 1.2 : 0.9,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF2D87FF)
                        : Colors.white.withValues(alpha: 0.24),
                    width: 2,
                  ),
                  color: selected
                      ? const Color(0xFF2D87FF)
                      : Colors.transparent,
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF3F99FF)
                            : Colors.white,
                        fontSize: title.length > 12 ? 13.5 : 14.5,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xB3FFFFFF),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (trailingDetail.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                trailingDetail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0x85FFFFFF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 10),
                _SubtitleDeleteButton(
                  deleting: deleting,
                  onTap: deleting ? null : onDelete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleSearchResultTile extends StatelessWidget {
  final String title;
  final String meta;
  final int downloads;
  final bool loading;
  final VoidCallback onTap;

  const _SubtitleSearchResultTile({
    required this.title,
    required this.meta,
    required this.downloads,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x332D87FF)),
            color: Colors.white.withValues(alpha: 0.03),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: title.length > 26 ? 13.5 : 14.5,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          color: Color(0x99FFFFFF),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$downloads',
                          style: const TextStyle(
                            color: Color(0x99FFFFFF),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0x99FFFFFF),
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.download_for_offline_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleDeleteButton extends StatelessWidget {
  final bool deleting;
  final VoidCallback? onTap;

  const _SubtitleDeleteButton({required this.deleting, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: deleting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: Colors.white70,
                  ),
                )
              : Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.72),
                  size: 20,
                ),
        ),
      ),
    );
  }
}

class _SubtitleAdjustRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _SubtitleAdjustRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _SubtitleActionCapsule extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SubtitleActionCapsule({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1F2B52),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 56,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubtitleValueCapsule extends StatelessWidget {
  final String label;

  const _SubtitleValueCapsule({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
