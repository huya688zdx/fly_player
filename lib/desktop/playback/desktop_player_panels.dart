import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';

import '../../danmaku/models/danmaku_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../playback/bookmarks/bookmark_store.dart';
import '../../playback/playback_source.dart';
import '../../playback/settings/mpv_settings_l10n.dart';
import '../../playback/settings/mpv_settings_store.dart';

class DesktopPlayerPanelOption {
  const DesktopPlayerPanelOption({
    required this.value,
    required this.title,
    this.subtitle = '',
    this.selected = false,
  });
  final Object value;
  final String title;
  final String subtitle;
  final bool selected;
}

class DesktopTrackPanel extends StatelessWidget {
  const DesktopTrackPanel({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.offLabel,
    required this.options,
    required this.onSelected,
    this.onOff,
  });
  final String title, emptyLabel, offLabel;
  final List<DesktopPlayerPanelOption> options;
  final ValueChanged<DesktopPlayerPanelOption> onSelected;
  final VoidCallback? onOff;
  @override
  Widget build(BuildContext context) => _PanelScroll(
    children: [
      _PanelTitle(title, '选择要输出的轨道'),
      const SizedBox(height: 16),
      if (onOff != null) ...[
        _OptionCard(offLabel, icon: Icons.block_rounded, onTap: onOff),
        const SizedBox(height: 8),
      ],
      if (options.isEmpty)
        _EmptyPanel(emptyLabel)
      else
        ...options.map(
          (option) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionCard(
              option.title,
              subtitle: option.subtitle,
              selected: option.selected,
              onTap: () => onSelected(option),
            ),
          ),
        ),
    ],
  );
}

class DesktopEpisodePanel extends StatefulWidget {
  const DesktopEpisodePanel({
    super.key,
    required this.title,
    required this.emptyLabel,
    required this.episodes,
    required this.onSelected,
    this.currentItemGuid = '',
    this.seriesTitle = '',
  });
  final String title, emptyLabel, currentItemGuid, seriesTitle;
  final List<Map<String, dynamic>> episodes;
  final ValueChanged<Map<String, dynamic>>? onSelected;
  @override
  State<DesktopEpisodePanel> createState() => _DesktopEpisodePanelState();
}

class _DesktopEpisodePanelState extends State<DesktopEpisodePanel> {
  bool _grid = false;
  final ScrollController _listScrollController = ScrollController();
  final ScrollController _gridScrollController = ScrollController();

  @override
  void dispose() {
    _listScrollController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _PanelTitle(widget.title, widget.seriesTitle)),
              _ViewToggle(
                Icons.view_list_rounded,
                !_grid,
                () => setState(() => _grid = false),
              ),
              _ViewToggle(
                Icons.grid_view_rounded,
                _grid,
                () => setState(() => _grid = true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.episodes.isEmpty
                ? _EmptyPanel(widget.emptyLabel)
                : _grid
                ? GridView.builder(
                    controller: _gridScrollController,
                    padding: const EdgeInsets.only(right: 14),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisExtent: 58,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: widget.episodes.length,
                    itemBuilder: (_, i) => _EpisodeNumberTile(
                      episode: widget.episodes[i],
                      fallbackNumber: i + 1,
                      current: _isCurrent(widget.episodes[i]),
                      enabled: widget.onSelected != null,
                      onTap: widget.onSelected == null
                          ? null
                          : () => widget.onSelected!(widget.episodes[i]),
                    ),
                  )
                : ListView.separated(
                    controller: _listScrollController,
                    padding: const EdgeInsets.only(right: 14),
                    itemCount: widget.episodes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _EpisodeCard(
                      widget.episodes[i],
                      _isCurrent(widget.episodes[i]),
                      widget.onSelected != null,
                      false,
                      widget.onSelected == null
                          ? null
                          : () => widget.onSelected!(widget.episodes[i]),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
  bool _isCurrent(Map<String, dynamic> e) =>
      '${e['itemGuid'] ?? e['guid'] ?? ''}'.trim() ==
          widget.currentItemGuid.trim() &&
      widget.currentItemGuid.trim().isNotEmpty;
}

class _EpisodeNumberTile extends StatefulWidget {
  const _EpisodeNumberTile({
    required this.episode,
    required this.fallbackNumber,
    required this.current,
    required this.enabled,
    required this.onTap,
  });

  final Map<String, dynamic> episode;
  final int fallbackNumber;
  final bool current;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  State<_EpisodeNumberTile> createState() => _EpisodeNumberTileState();
}

class _EpisodeNumberTileState extends State<_EpisodeNumberTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final shortLabel = '${widget.episode['shortLabel'] ?? ''}'.trim();
    final episodeNumber = '${widget.episode['episodeNumber'] ?? ''}'.trim();
    final label = shortLabel.isNotEmpty
        ? shortLabel
        : (episodeNumber.isNotEmpty
              ? episodeNumber
              : '${widget.fallbackNumber}');
    final watched =
        widget.episode['watched'] == true || widget.episode['watched'] == 1;
    final active = widget.current || _hovered;

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && widget.enabled ? 1.04 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.current
                ? const Color(0x2963A0FF)
                : (_hovered
                      ? const Color(0x1FFFFFFF)
                      : const Color(0x0DFFFFFF)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? const Color(0x8063A0FF) : const Color(0x20FFFFFF),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.onTap,
              child: Stack(
                children: <Widget>[
                  Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.current
                            ? const Color(0xFF63A0FF)
                            : Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (watched)
                    Positioned(
                      right: 5,
                      bottom: 4,
                      child: Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: widget.current
                            ? const Color(0xFF8DB9FF)
                            : Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopDanmakuSettingsPanel extends StatefulWidget {
  const DesktopDanmakuSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  final DanmakuSettings settings;
  final Future<void> Function(DanmakuSettings settings) onChanged;

  @override
  State<DesktopDanmakuSettingsPanel> createState() =>
      _DesktopDanmakuSettingsPanelState();
}

class _DesktopDanmakuSettingsPanelState
    extends State<DesktopDanmakuSettingsPanel> {
  late DanmakuSettings _settings = widget.settings;

  Future<void> _update(DanmakuSettings next) async {
    setState(() => _settings = next);
    await widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SettingsHeader(title: '弹幕设置'),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  _SettingsSwitchTile(
                    title: '滚动弹幕',
                    subtitle: '从右向左滚动显示',
                    value: _settings.scrollEnabled,
                    onChanged: (value) =>
                        _update(_settings.copyWith(scrollEnabled: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: '顶部弹幕',
                    subtitle: '固定在画面顶部显示',
                    value: _settings.topEnabled,
                    onChanged: (value) =>
                        _update(_settings.copyWith(topEnabled: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: '底部弹幕',
                    subtitle: '固定在弹幕显示区域底部',
                    value: _settings.bottomEnabled,
                    onChanged: (value) =>
                        _update(_settings.copyWith(bottomEnabled: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: '保留弹幕颜色',
                    subtitle: '关闭后统一使用白色',
                    value: _settings.colorEnabled,
                    onChanged: (value) =>
                        _update(_settings.copyWith(colorEnabled: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: '隐藏重复弹幕',
                    subtitle: '同一时间窗口只显示一次相同内容',
                    value: _settings.hideDuplicate,
                    onChanged: (value) =>
                        _update(_settings.copyWith(hideDuplicate: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: '避让字幕区域',
                    subtitle: '减少弹幕与底部字幕重叠',
                    value: _settings.avoidSubtitleArea,
                    onChanged: (value) =>
                        _update(_settings.copyWith(avoidSubtitleArea: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSwitchTile(
                    title: '避让画面中心',
                    subtitle: '优先把弹幕限制在画面上部',
                    value: _settings.avoidCenterArea,
                    onChanged: (value) =>
                        _update(_settings.copyWith(avoidCenterArea: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: '不透明度',
                    valueLabel: '${(_settings.opacity * 100).round()}%',
                    value: _settings.opacity,
                    min: 0.2,
                    max: 1,
                    divisions: 16,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(opacity: value),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(opacity: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: '显示密度',
                    valueLabel: '${(_settings.density * 100).round()}%',
                    value: _settings.density,
                    min: 0.2,
                    max: 1,
                    divisions: 16,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(density: value),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(density: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: '字体大小',
                    valueLabel: '${(_settings.fontScale * 100).round()}%',
                    value: _settings.fontScale,
                    min: 0.6,
                    max: 1.4,
                    divisions: 16,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(fontScale: value),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(fontScale: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: '字体粗细',
                    valueLabel: _settings.fontThickness.toStringAsFixed(1),
                    value: _settings.fontThickness,
                    min: 0.8,
                    max: 1.4,
                    divisions: 6,
                    onChanged: (value) => setState(
                      () =>
                          _settings = _settings.copyWith(fontThickness: value),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(fontThickness: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: '滚动速度',
                    valueLabel: '${_settings.speed.toStringAsFixed(2)}×',
                    value: _settings.speed,
                    min: danmakuSpeedMin,
                    max: danmakuSpeedMax,
                    divisions: danmakuSpeedDivisions,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(speed: value),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(speed: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: '显示区域',
                    valueLabel:
                        '${(_settings.displayAreaRatio * 100).round()}%',
                    value: _settings.displayAreaRatio,
                    min: 0.25,
                    max: 1,
                    divisions: 3,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(
                        displayAreaRatio: value,
                      ),
                    ),
                    onChangeEnd: (value) =>
                        _update(_settings.copyWith(displayAreaRatio: value)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsSliderTile(
                    title: '刷新率',
                    valueLabel: '${_settings.targetFrameRateHz} Hz',
                    value: _settings.targetFrameRateHz.toDouble(),
                    min: 30,
                    max: 120,
                    divisions: 6,
                    onChanged: (value) => setState(
                      () => _settings = _settings.copyWith(
                        targetFrameRateHz: value.round(),
                      ),
                    ),
                    onChangeEnd: (value) => _update(
                      _settings.copyWith(targetFrameRateHz: value.round()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DesktopDanmakuSourcePanel extends StatefulWidget {
  const DesktopDanmakuSourcePanel({
    super.key,
    required this.currentSourceLabel,
    required this.commentCount,
    required this.loading,
    required this.initialKeyword,
    required this.onLoadSavedSources,
    required this.onSearch,
    required this.onSelectSavedSource,
    required this.onSelectSearchResult,
    required this.onDeleteSavedSource,
    required this.onImportFile,
  });

  final String currentSourceLabel;
  final int commentCount;
  final bool loading;
  final String initialKeyword;
  final Future<List<Map<String, dynamic>>> Function() onLoadSavedSources;
  final Future<List<Map<String, dynamic>>> Function(String keyword) onSearch;
  final Future<bool> Function(Map<String, dynamic> source) onSelectSavedSource;
  final Future<bool> Function(Map<String, dynamic> result) onSelectSearchResult;
  final Future<void> Function(Map<String, dynamic> source) onDeleteSavedSource;
  final Future<bool> Function() onImportFile;

  @override
  State<DesktopDanmakuSourcePanel> createState() =>
      _DesktopDanmakuSourcePanelState();
}

class _DesktopDanmakuSourcePanelState extends State<DesktopDanmakuSourcePanel> {
  late final TextEditingController _searchController = TextEditingController(
    text: widget.initialKeyword,
  );
  List<Map<String, dynamic>> _savedSources = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _searchResults = const <Map<String, dynamic>>[];
  bool _loadingSources = true;
  bool _searching = false;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedSources());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSources() async {
    if (mounted) setState(() => _loadingSources = true);
    final sources = await widget.onLoadSavedSources();
    if (!mounted) return;
    setState(() {
      _savedSources = sources;
      _loadingSources = false;
    });
  }

  Future<void> _search() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty || _searching) return;
    setState(() => _searching = true);
    final results = await widget.onSearch(keyword);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  Future<void> _applySaved(Map<String, dynamic> source) async {
    if (_applying) return;
    setState(() => _applying = true);
    final applied = await widget.onSelectSavedSource(source);
    if (!mounted) return;
    if (applied) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _applying = false);
  }

  Future<void> _applySearchResult(Map<String, dynamic> result) async {
    if (_applying) return;
    setState(() => _applying = true);
    final applied = await widget.onSelectSearchResult(result);
    if (!mounted) return;
    if (applied) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _applying = false);
  }

  Future<void> _import() async {
    if (_applying) return;
    setState(() => _applying = true);
    final applied = await widget.onImportFile();
    if (!mounted) return;
    if (applied) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _applying = false);
  }

  Future<void> _delete(Map<String, dynamic> source) async {
    if (_applying) return;
    await widget.onDeleteSavedSource(source);
    await _loadSavedSources();
  }

  @override
  Widget build(BuildContext context) {
    final currentSource = widget.currentSourceLabel.trim();
    final currentStatus = widget.loading
        ? '正在加载'
        : widget.commentCount > 0
        ? '${widget.commentCount} 条'
        : '暂无弹幕';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SettingsHeader(title: '弹幕源'),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: <Widget>[
                  _SettingsStatusCard(
                    title: '当前弹幕源',
                    value: currentSource.isEmpty ? '未选择' : currentSource,
                    description: currentStatus,
                  ),
                  const SizedBox(height: 10),
                  _SettingsMenuTile(
                    title: '导入本地弹幕',
                    subtitle: '支持 XML 与 JSON 文件',
                    icon: Icons.file_open_rounded,
                    onTap: () => unawaited(_import()),
                  ),
                  const SizedBox(height: 18),
                  const _DanmakuSectionTitle('在线搜索'),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: (_) => unawaited(_search()),
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '输入作品名搜索弹弹play',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0x14FFFFFF),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          tooltip: '搜索',
                          onPressed: _searching
                              ? null
                              : () => unawaited(_search()),
                          icon: _searching
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ),
                  if (_searchResults.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    for (final result in _searchResults) ...<Widget>[
                      _DanmakuSourceTile(
                        title: '${result['title'] ?? '弹弹play'}',
                        subtitle: '${result['subtitle'] ?? ''}',
                        trailing: result['matchesCurrentSeason'] == true
                            ? '当前季'
                            : '',
                        onTap: _applying
                            ? null
                            : () => unawaited(_applySearchResult(result)),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  const SizedBox(height: 10),
                  const _DanmakuSectionTitle('已保存弹幕源'),
                  const SizedBox(height: 8),
                  if (_loadingSources)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_savedSources.isEmpty)
                    const _SettingsStatusCard(
                      title: '来源库',
                      value: '暂无已保存来源',
                      description: '在线匹配、随片下载和本地导入的来源会显示在这里。',
                    )
                  else
                    for (final source in _savedSources) ...<Widget>[
                      _DanmakuSourceTile(
                        title:
                            '${source['label'] ?? source['sourceKey'] ?? ''}',
                        subtitle: _savedSourceSubtitle(source),
                        selected: source['active'] == true,
                        trailing: source['active'] == true ? '使用中' : '',
                        onTap: _applying
                            ? null
                            : () => unawaited(_applySaved(source)),
                        onDelete: () => unawaited(_delete(source)),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _savedSourceSubtitle(Map<String, dynamic> source) {
    final type = switch ('${source['type'] ?? ''}') {
      'danDanPlay' => '弹弹play',
      'downloadedFile' => '随片下载',
      _ => '本地',
    };
    final count = (source['commentCount'] as num?)?.toInt() ?? 0;
    final detail = '${source['detail'] ?? ''}'.trim();
    return <String>[
      type,
      if (count > 0) '$count 条',
      if (detail.isNotEmpty) detail,
    ].join(' · ');
  }
}

class _DanmakuSectionTitle extends StatelessWidget {
  const _DanmakuSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      color: Colors.white60,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _DanmakuSourceTile extends StatelessWidget {
  const _DanmakuSourceTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing = '',
    this.selected = false,
    this.onDelete,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    selected: selected,
    onTap: onTap,
    child: Row(
      children: <Widget>[
        Icon(
          selected ? Icons.check_circle_rounded : Icons.comment_bank_outlined,
          color: selected ? const Color(0xFF9CC4FF) : Colors.white54,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SettingsTileText(title: title, subtitle: subtitle),
        ),
        if (trailing.trim().isNotEmpty) ...<Widget>[
          const SizedBox(width: 10),
          Text(
            trailing,
            style: const TextStyle(color: Color(0xFF9CC4FF), fontSize: 11),
          ),
        ],
        if (onDelete != null) ...<Widget>[
          const SizedBox(width: 6),
          IconButton(
            tooltip: '删除来源',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            color: Colors.white54,
          ),
        ],
      ],
    ),
  );
}

class DesktopPlaybackSettingsPanel extends StatefulWidget {
  const DesktopPlaybackSettingsPanel({
    super.key,
    required this.source,
    required this.position,
    required this.autoPlayEnabled,
    required this.nextEpisodePreloadEnabled,
    required this.aspectRatioMode,
    required this.decoderMode,
    required this.cacheSizeMb,
    required this.mpvSettings,
    required this.videoAdjustments,
    required this.audioDelaySeconds,
    required this.bookmarks,
    required this.danmakuEnabled,
    required this.danmakuSourceLabel,
    required this.danmakuCommentCount,
    required this.onAutoPlayChanged,
    required this.onNextEpisodePreloadChanged,
    required this.onAspectRatioChanged,
    required this.onDecoderChanged,
    required this.onCacheSizeChanged,
    required this.onMpvAudioSettingChanged,
    required this.onVideoAdjustmentChanged,
    required this.onAudioDelayChanged,
    required this.onAddBookmark,
    required this.onDeleteBookmark,
    required this.onSelectBookmark,
    required this.onOpenDanmakuSettings,
    required this.onOpenDanmakuSources,
  });

  final MpvMediaSource source;
  final Duration position;
  final bool autoPlayEnabled;
  final bool nextEpisodePreloadEnabled;
  final String aspectRatioMode;
  final String decoderMode;
  final int cacheSizeMb;
  final Map<String, String> mpvSettings;
  final Map<String, double> videoAdjustments;
  final double audioDelaySeconds;
  final List<PlayerBookmarkEntry> bookmarks;
  final bool danmakuEnabled;
  final String danmakuSourceLabel;
  final int danmakuCommentCount;
  final Future<void> Function(bool value) onAutoPlayChanged;
  final Future<void> Function(bool value) onNextEpisodePreloadChanged;
  final Future<void> Function(String value) onAspectRatioChanged;
  final Future<void> Function(String value) onDecoderChanged;
  final Future<void> Function(int value) onCacheSizeChanged;
  final Future<void> Function(String key, String value)
  onMpvAudioSettingChanged;
  final Future<void> Function(String key, double value)
  onVideoAdjustmentChanged;
  final Future<void> Function(double value) onAudioDelayChanged;
  final Future<List<PlayerBookmarkEntry>> Function() onAddBookmark;
  final Future<List<PlayerBookmarkEntry>> Function(PlayerBookmarkEntry entry)
  onDeleteBookmark;
  final Future<void> Function(PlayerBookmarkEntry entry) onSelectBookmark;
  final VoidCallback onOpenDanmakuSettings;
  final VoidCallback onOpenDanmakuSources;

  @override
  State<DesktopPlaybackSettingsPanel> createState() =>
      _DesktopPlaybackSettingsPanelState();
}

enum _DesktopSettingsPage {
  main,
  advanced,
  aspectRatio,
  bookmarks,
  mpv,
  videoAdjust,
  audioAdjust,
  audioChoice,
  decoder,
  cache,
  videoInfo,
}

class _DesktopPlaybackSettingsPanelState
    extends State<DesktopPlaybackSettingsPanel> {
  final List<_DesktopSettingsPage> _pages = <_DesktopSettingsPage>[
    _DesktopSettingsPage.main,
  ];
  late bool _autoPlayEnabled = widget.autoPlayEnabled;
  late bool _nextEpisodePreloadEnabled = widget.nextEpisodePreloadEnabled;
  late String _aspectRatioMode = widget.aspectRatioMode;
  late String _decoderMode = widget.decoderMode;
  late int _cacheSizeMb = widget.cacheSizeMb;
  late Map<String, String> _mpvSettings = Map<String, String>.from(
    widget.mpvSettings,
  );
  late Map<String, double> _videoAdjustments = Map<String, double>.from(
    widget.videoAdjustments,
  );
  late double _audioDelaySeconds = widget.audioDelaySeconds;
  String _audioChoiceKey = '';
  late List<PlayerBookmarkEntry> _bookmarks = List<PlayerBookmarkEntry>.from(
    widget.bookmarks,
  );

  _DesktopSettingsPage get _page => _pages.last;

  void _push(_DesktopSettingsPage page) => setState(() => _pages.add(page));

  void _pop() {
    if (_pages.length <= 1) return;
    setState(() => _pages.removeLast());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _SettingsHeader(
              title: _pageTitle(l10n),
              onBack: _pages.length > 1 ? _pop : null,
              action: switch (_page) {
                _DesktopSettingsPage.main => IconButton(
                  tooltip: l10n.playerAdvancedSettingsTitle,
                  onPressed: () => _push(_DesktopSettingsPage.advanced),
                  icon: const Icon(Icons.settings_rounded),
                  color: Colors.white70,
                ),
                _DesktopSettingsPage.bookmarks => IconButton(
                  tooltip: l10n.playerBookmarkAddCurrent,
                  onPressed: _addBookmark,
                  icon: const Icon(Icons.add_rounded),
                  color: Colors.white70,
                ),
                _DesktopSettingsPage.videoAdjust => IconButton(
                  tooltip: l10n.commonReset,
                  onPressed: () => _resetVideoAdjustments(),
                  icon: const Icon(Icons.restart_alt_rounded),
                  color: Colors.white70,
                ),
                _ => null,
              },
            ),
            const SizedBox(height: 18),
            Expanded(child: _buildPage(l10n)),
          ],
        ),
      ),
    );
  }

  String _pageTitle(AppLocalizations l10n) => switch (_page) {
    _DesktopSettingsPage.main => l10n.playerSettingsTitle,
    _DesktopSettingsPage.advanced => l10n.playerAdvancedSettingsTitle,
    _DesktopSettingsPage.aspectRatio => l10n.playerAspectRatioTitle,
    _DesktopSettingsPage.bookmarks => l10n.playerBookmarkTitle,
    _DesktopSettingsPage.mpv => l10n.settingsMpvTitle,
    _DesktopSettingsPage.videoAdjust => l10n.mpvInstantAdjustTitle,
    _DesktopSettingsPage.audioAdjust => '音频调整',
    _DesktopSettingsPage.audioChoice => _audioChoiceTitle(l10n),
    _DesktopSettingsPage.decoder => l10n.playerDecoderTitle,
    _DesktopSettingsPage.cache => l10n.playerCacheSettingsTitle,
    _DesktopSettingsPage.videoInfo => l10n.playerVideoInfoTitle,
  };

  Widget _buildPage(AppLocalizations l10n) => switch (_page) {
    _DesktopSettingsPage.main => _buildMainPage(l10n),
    _DesktopSettingsPage.advanced => _buildAdvancedPage(l10n),
    _DesktopSettingsPage.aspectRatio => _buildAspectRatioPage(l10n),
    _DesktopSettingsPage.bookmarks => _buildBookmarksPage(l10n),
    _DesktopSettingsPage.mpv => _buildMpvPage(l10n),
    _DesktopSettingsPage.videoAdjust => _buildVideoAdjustPage(l10n),
    _DesktopSettingsPage.audioAdjust => _buildAudioAdjustPage(l10n),
    _DesktopSettingsPage.audioChoice => _buildAudioChoicePage(l10n),
    _DesktopSettingsPage.decoder => _buildDecoderPage(l10n),
    _DesktopSettingsPage.cache => _buildCachePage(l10n),
    _DesktopSettingsPage.videoInfo => _buildVideoInfoPage(l10n),
  };

  Widget _settingsList(List<Widget> children) => ListView.separated(
    padding: EdgeInsets.zero,
    itemCount: children.length,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (_, index) => children[index],
  );

  Widget _buildMainPage(AppLocalizations l10n) => _settingsList(<Widget>[
    _SettingsSwitchTile(
      title: l10n.playerAutoPlayTitle,
      subtitle: _autoPlayEnabled
          ? l10n.playerAutoPlayEnabledSubtitle
          : l10n.playerAutoPlayDisabledSubtitle,
      value: _autoPlayEnabled,
      onChanged: _setAutoPlay,
    ),
    _SettingsSwitchTile(
      title: l10n.playerNextEpisodePreloadTitle,
      subtitle: !_autoPlayEnabled
          ? l10n.playerNextEpisodePreloadRequiresAutoPlay
          : _nextEpisodePreloadEnabled
          ? l10n.playerNextEpisodePreloadEnabledSubtitle
          : l10n.playerNextEpisodePreloadDisabledSubtitle,
      value: _nextEpisodePreloadEnabled,
      enabled: _autoPlayEnabled,
      onChanged: _setNextEpisodePreload,
    ),
    _SettingsMenuTile(
      title: l10n.playerAspectRatioTitle,
      subtitle: l10n.playerCurrentValue(_aspectLabel(l10n)),
      icon: Icons.aspect_ratio_rounded,
      onTap: () => _push(_DesktopSettingsPage.aspectRatio),
    ),
    _SettingsMenuTile(
      title: l10n.playerBookmarkTitle,
      subtitle: l10n.playerBookmarkSettingsSubtitle,
      trailing: _bookmarks.isEmpty
          ? l10n.playerBookmarkNone
          : l10n.playerBookmarkCount(_bookmarks.length),
      icon: Icons.bookmark_outline_rounded,
      onTap: () => _push(_DesktopSettingsPage.bookmarks),
    ),
    _SettingsMenuTile(
      title: l10n.settingsMpvTitle,
      subtitle: 'Windows media_kit / libmpv',
      trailing: _decoderMode == 'software'
          ? l10n.playerSoftwareDecoderTitle
          : l10n.playerHardwareDecoderTitle,
      icon: Icons.tune_rounded,
      onTap: () => _push(_DesktopSettingsPage.mpv),
    ),
    _SettingsMenuTile(
      title: '弹幕设置',
      subtitle: '显示区域、透明度、密度、字号与弹幕类型',
      trailing: widget.danmakuEnabled ? '已开启' : '已关闭',
      icon: Icons.format_size_rounded,
      onTap: widget.onOpenDanmakuSettings,
    ),
    _SettingsMenuTile(
      title: '弹幕源',
      subtitle: widget.danmakuSourceLabel.trim().isEmpty
          ? '在线搜索、本地导入与已保存来源'
          : widget.danmakuSourceLabel,
      trailing: widget.danmakuCommentCount > 0
          ? '${widget.danmakuCommentCount} 条'
          : '',
      icon: Icons.comment_bank_outlined,
      onTap: widget.onOpenDanmakuSources,
    ),
  ]);

  Widget _buildAdvancedPage(AppLocalizations l10n) => _settingsList(<Widget>[
    _SettingsMenuTile(
      title: l10n.playerDecoderTitle,
      subtitle: l10n.playerDecoderSubtitle,
      trailing: _decoderMode == 'software'
          ? l10n.playerSoftwareDecoderTitle
          : l10n.playerHardwareDecoderTitle,
      icon: Icons.memory_rounded,
      onTap: () => _push(_DesktopSettingsPage.decoder),
    ),
    _SettingsMenuTile(
      title: l10n.playerCacheSettingsTitle,
      subtitle: l10n.playerCacheSettingsSubtitle,
      trailing: _cacheSizeMb <= 0 ? '自动' : '$_cacheSizeMb MB',
      icon: Icons.storage_rounded,
      onTap: () => _push(_DesktopSettingsPage.cache),
    ),
    _SettingsMenuTile(
      title: l10n.playerVideoInfoTitle,
      subtitle: l10n.playerVideoInfoSubtitle,
      icon: Icons.info_outline_rounded,
      onTap: () => _push(_DesktopSettingsPage.videoInfo),
    ),
  ]);

  Widget _buildMpvPage(AppLocalizations l10n) => _settingsList(<Widget>[
    _SettingsStatusCard(
      title: 'Windows libmpv',
      value: _decoderMode == 'software'
          ? l10n.playerSoftwareDecoderTitle
          : l10n.playerHardwareDecoderTitle,
      description: '设置直接应用到当前桌面播放实例。',
    ),
    _SettingsMenuTile(
      title: l10n.mpvInstantAdjustTitle,
      subtitle: l10n.mpvVideoAdjustDrawerDescription,
      trailing:
          MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments) == 0
          ? l10n.mpvDefault
          : l10n.mpvChangedCount(
              MpvSettingsCatalog.videoAdjustmentChangedCount(_videoAdjustments),
            ),
      icon: Icons.display_settings_rounded,
      onTap: () => _push(_DesktopSettingsPage.videoAdjust),
    ),
    _SettingsMenuTile(
      title: '音频调整',
      subtitle: '音频延迟、增益、EQ、动态范围与声道输出',
      trailing:
          MpvSettingsCatalog.changedCount(
                _mpvSettings,
                MpvSettingsCatalog.audioPresetKeys,
              ) ==
              0
          ? l10n.mpvDefault
          : l10n.mpvChangedCount(
              MpvSettingsCatalog.changedCount(
                _mpvSettings,
                MpvSettingsCatalog.audioPresetKeys,
              ),
            ),
      icon: Icons.graphic_eq_rounded,
      onTap: () => _push(_DesktopSettingsPage.audioAdjust),
    ),
    _SettingsMenuTile(
      title: l10n.playerDecoderTitle,
      subtitle: l10n.playerDecoderSubtitle,
      trailing: _decoderMode == 'software'
          ? l10n.playerSoftwareDecoderTitle
          : l10n.playerHardwareDecoderTitle,
      icon: Icons.memory_rounded,
      onTap: () => _push(_DesktopSettingsPage.decoder),
    ),
    _SettingsMenuTile(
      title: l10n.playerCacheSettingsTitle,
      subtitle: l10n.playerCacheSettingsSubtitle,
      trailing: _cacheSizeMb <= 0 ? '自动' : '$_cacheSizeMb MB',
      icon: Icons.storage_rounded,
      onTap: () => _push(_DesktopSettingsPage.cache),
    ),
    _SettingsMenuTile(
      title: l10n.playerAspectRatioTitle,
      subtitle: l10n.playerCurrentValue(_aspectLabel(l10n)),
      icon: Icons.aspect_ratio_rounded,
      onTap: () => _push(_DesktopSettingsPage.aspectRatio),
    ),
  ]);

  Widget _buildVideoAdjustPage(AppLocalizations l10n) => _settingsList(<Widget>[
    for (final key in MpvSettingsCatalog.videoAdjustmentDefaults.keys)
      _SettingsSliderTile(
        title: MpvSettingsL10n.videoAdjustmentTitle(l10n, key),
        subtitle: MpvSettingsL10n.videoAdjustmentSubtitle(l10n, key),
        valueLabel: MpvSettingsCatalog.formatVideoAdjustmentValue(
          _videoAdjustments[key] ?? 0,
        ),
        value: _videoAdjustments[key] ?? 0,
        min: -100,
        max: 100,
        divisions: 200,
        onChanged: (value) => setState(
          () => _videoAdjustments = <String, double>{
            ..._videoAdjustments,
            key: value,
          },
        ),
        onChangeEnd: (value) => _setVideoAdjustment(key, value),
      ),
  ]);

  Widget _buildAudioAdjustPage(AppLocalizations l10n) {
    const keys = <String>[
      MpvSettingsCatalog.volumeGainKey,
      MpvSettingsCatalog.audioHighFidelityKey,
      MpvSettingsCatalog.dynamicRangeKey,
      MpvSettingsCatalog.audioEqKey,
      MpvSettingsCatalog.audioLimiterKey,
      MpvSettingsCatalog.audioBassBoostKey,
      MpvSettingsCatalog.audioVoiceEnhanceKey,
      MpvSettingsCatalog.channelMixKey,
      MpvSettingsCatalog.audioPassthroughKey,
    ];
    return _settingsList(<Widget>[
      _SettingsSliderTile(
        title: '音频延迟',
        subtitle: '正值让声音更晚，负值让声音更早',
        valueLabel:
            '${_audioDelaySeconds > 0 ? '+' : ''}${_audioDelaySeconds.toStringAsFixed(1)} 秒',
        value: _audioDelaySeconds,
        min: -10,
        max: 10,
        divisions: 200,
        onChanged: (value) => setState(() => _audioDelaySeconds = value),
        onChangeEnd: _setAudioDelay,
      ),
      for (final key in keys)
        _SettingsMenuTile(
          title: MpvSettingsL10n.definitionByKey(l10n, key)?.title ?? key,
          subtitle:
              MpvSettingsL10n.definitionByKey(l10n, key)?.description ?? '',
          trailing: MpvSettingsL10n.labelForSetting(l10n, key, _mpvSettings),
          icon: key == MpvSettingsCatalog.audioEqKey
              ? Icons.equalizer_rounded
              : Icons.tune_rounded,
          onTap: () {
            _audioChoiceKey = key;
            _push(_DesktopSettingsPage.audioChoice);
          },
        ),
      if (_mpvSettings[MpvSettingsCatalog.audioEqKey] ==
          MpvSettingsCatalog.audioEqCustomValue)
        for (final band in MpvSettingsCatalog.audioEqBands)
          _SettingsSliderTile(
            title: '${band.label} Hz',
            subtitle: '自定义均衡器频段',
            valueLabel: MpvSettingsCatalog.formatAudioEqBandValue(
              MpvSettingsCatalog.audioEqBandValue(band.key, _mpvSettings),
            ),
            value: MpvSettingsCatalog.audioEqBandValue(band.key, _mpvSettings),
            min: MpvSettingsCatalog.audioEqBandMinDb,
            max: MpvSettingsCatalog.audioEqBandMaxDb,
            divisions:
                ((MpvSettingsCatalog.audioEqBandMaxDb -
                            MpvSettingsCatalog.audioEqBandMinDb) /
                        MpvSettingsCatalog.audioEqBandStepDb)
                    .round(),
            onChanged: (value) => setState(
              () => _mpvSettings = <String, String>{
                ..._mpvSettings,
                band.key: MpvSettingsCatalog.normalizeAudioEqBandValue(value),
              },
            ),
            onChangeEnd: (value) => _setMpvAudioSetting(
              band.key,
              MpvSettingsCatalog.normalizeAudioEqBandValue(value),
            ),
          ),
    ]);
  }

  Widget _buildAudioChoicePage(AppLocalizations l10n) {
    final definition = MpvSettingsL10n.definitionByKey(l10n, _audioChoiceKey);
    if (definition == null) {
      return const _SettingsStatusCard(
        title: '音频设置',
        value: '不可用',
        description: '',
      );
    }
    final current =
        _mpvSettings[definition.key] ??
        MpvSettingsCatalog.defaults[definition.key] ??
        '';
    return _settingsList(<Widget>[
      for (final option in definition.options)
        _SettingsChoiceTile(
          title: option.label,
          subtitle: option.description,
          selected: current == option.value,
          onTap: () => _setAudioChoice(definition.key, option.value),
        ),
    ]);
  }

  String _audioChoiceTitle(AppLocalizations l10n) {
    return MpvSettingsL10n.definitionByKey(l10n, _audioChoiceKey)?.title ??
        '音频设置';
  }

  Widget _buildAspectRatioPage(AppLocalizations l10n) => _settingsList(<Widget>[
    _SettingsChoiceTile(
      title: l10n.playerAspectFit,
      selected: _aspectRatioMode == 'fit',
      onTap: () => _setAspectRatio('fit'),
    ),
    _SettingsChoiceTile(
      title: l10n.playerAspectFill,
      selected: _aspectRatioMode == 'fill',
      onTap: () => _setAspectRatio('fill'),
    ),
    for (final ratio in const <String>['4:3', '16:9', '21:9'])
      _SettingsChoiceTile(
        title: ratio,
        selected: _aspectRatioMode == ratio,
        onTap: () => _setAspectRatio(ratio),
      ),
  ]);

  Widget _buildDecoderPage(AppLocalizations l10n) => _settingsList(<Widget>[
    _SettingsChoiceTile(
      title: l10n.playerHardwareDecoderTitle,
      subtitle: l10n.playerHardwareDecoderSubtitle,
      selected: _decoderMode != 'software',
      onTap: () => _setDecoder('hardware'),
    ),
    _SettingsChoiceTile(
      title: l10n.playerSoftwareDecoderTitle,
      subtitle: l10n.playerSoftwareDecoderSubtitle,
      selected: _decoderMode == 'software',
      onTap: () => _setDecoder('software'),
    ),
  ]);

  Widget _buildCachePage(AppLocalizations l10n) => _settingsList(<Widget>[
    for (final value in const <int>[0, 256, 512, 1024, 1984])
      _SettingsChoiceTile(
        title: value == 0 ? '自动' : '$value MB',
        selected: _cacheSizeMb == value,
        onTap: () => _setCacheSize(value),
      ),
  ]);

  Widget _buildBookmarksPage(AppLocalizations l10n) {
    if (_bookmarks.isEmpty) {
      return _settingsList(<Widget>[
        _SettingsStatusCard(
          title: widget.source.title,
          value: l10n.playerBookmarkNone,
          description: l10n.playerBookmarkEmptyPrompt,
        ),
      ]);
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _bookmarks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final entry = _bookmarks[index];
        return _BookmarkTile(
          time: _duration(entry.position),
          note: entry.note,
          onTap: () => widget.onSelectBookmark(entry),
          onDelete: () => _deleteBookmark(entry),
        );
      },
    );
  }

  Widget _buildVideoInfoPage(AppLocalizations l10n) {
    final source = widget.source;
    final dimensions = source.videoWidth > 0 && source.videoHeight > 0
        ? '${source.videoWidth} × ${source.videoHeight}'
        : source.resolution;
    final rows = <(String, String)>[
      ('标题', source.title),
      ('位置', _duration(widget.position)),
      ('时长', _duration(Duration(seconds: source.durationSeconds))),
      ('分辨率', dimensions),
      ('视频编码', source.videoCodecName),
      ('编码配置', source.videoProfile),
      ('位深', source.bitDepth > 0 ? '${source.bitDepth} bit' : ''),
      ('色彩空间', source.colorSpace),
      ('传输特性', source.colorTransfer),
      (
        '码率',
        source.bitrate > 0
            ? '${(source.bitrate / 1000000).toStringAsFixed(1)} Mbps'
            : '',
      ),
      ('播放模式', source.playbackMode.name),
    ].where((entry) => entry.$2.trim().isNotEmpty).toList(growable: false);
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(color: Color(0x18FFFFFF)),
      itemBuilder: (_, index) => _InfoRow(rows[index].$1, rows[index].$2),
    );
  }

  Future<void> _setAutoPlay(bool value) async {
    setState(() {
      _autoPlayEnabled = value;
      if (!value) _nextEpisodePreloadEnabled = false;
    });
    await widget.onAutoPlayChanged(value);
    if (!value) await widget.onNextEpisodePreloadChanged(false);
  }

  Future<void> _setNextEpisodePreload(bool value) async {
    if (!_autoPlayEnabled) return;
    setState(() => _nextEpisodePreloadEnabled = value);
    await widget.onNextEpisodePreloadChanged(value);
  }

  Future<void> _setAspectRatio(String value) async {
    setState(() => _aspectRatioMode = value);
    await widget.onAspectRatioChanged(value);
    if (mounted) _pop();
  }

  Future<void> _setDecoder(String value) async {
    setState(() => _decoderMode = value);
    await widget.onDecoderChanged(value);
    if (mounted) _pop();
  }

  Future<void> _setCacheSize(int value) async {
    setState(() => _cacheSizeMb = value);
    await widget.onCacheSizeChanged(value);
    if (mounted) _pop();
  }

  Future<void> _setVideoAdjustment(String key, double value) async {
    final next = Map<String, double>.from(_videoAdjustments)..[key] = value;
    final normalized = MpvSettingsCatalog.normalizeVideoAdjustments(next);
    setState(() => _videoAdjustments = normalized);
    await widget.onVideoAdjustmentChanged(key, normalized[key] ?? 0);
  }

  Future<void> _resetVideoAdjustments() async {
    final defaults = Map<String, double>.from(
      MpvSettingsCatalog.videoAdjustmentDefaults,
    );
    setState(() => _videoAdjustments = defaults);
    for (final entry in defaults.entries) {
      await widget.onVideoAdjustmentChanged(entry.key, entry.value);
    }
  }

  Future<void> _setMpvAudioSetting(String key, String value) async {
    setState(
      () => _mpvSettings = <String, String>{..._mpvSettings, key: value},
    );
    await widget.onMpvAudioSettingChanged(key, value);
  }

  Future<void> _setAudioChoice(String key, String value) async {
    await _setMpvAudioSetting(key, value);
    if (mounted) _pop();
  }

  Future<void> _setAudioDelay(double value) async {
    final normalized = double.parse(
      value.clamp(-10.0, 10.0).toStringAsFixed(1),
    );
    setState(() => _audioDelaySeconds = normalized);
    await widget.onAudioDelayChanged(normalized);
  }

  Future<void> _addBookmark() async {
    final next = await widget.onAddBookmark();
    if (mounted) setState(() => _bookmarks = next);
  }

  Future<void> _deleteBookmark(PlayerBookmarkEntry entry) async {
    final next = await widget.onDeleteBookmark(entry);
    if (mounted) setState(() => _bookmarks = next);
  }

  String _aspectLabel(AppLocalizations l10n) => switch (_aspectRatioMode) {
    'fill' => l10n.playerAspectFill,
    '4:3' || '16:9' || '21:9' => _aspectRatioMode,
    _ => l10n.playerAspectFit,
  };

  String _duration(Duration value) {
    final safe = value < Duration.zero ? Duration.zero : value;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.title, this.onBack, this.action});

  final String title;
  final VoidCallback? onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      if (onBack != null) ...<Widget>[
        IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: Colors.white,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(34),
            padding: EdgeInsets.zero,
            backgroundColor: const Color(0x14FFFFFF),
            hoverColor: const Color(0x28FFFFFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(width: 6),
      ],
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      if (action != null) action!,
      const SizedBox(width: 46),
    ],
  );
}

class _SettingsMenuTile extends StatelessWidget {
  const _SettingsMenuTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing = '',
    this.icon,
  });

  final String title;
  final String subtitle;
  final String trailing;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    onTap: onTap,
    child: Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0x1A6EA8FF),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 17, color: const Color(0xFF9CC4FF)),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: _SettingsTileText(title: title, subtitle: subtitle),
        ),
        if (trailing.trim().isNotEmpty) ...<Widget>[
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              trailing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ],
        const SizedBox(width: 8),
        const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: Colors.white30,
        ),
      ],
    ),
  );
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.52,
    child: _SettingsCard(
      onTap: enabled ? () => onChanged(!value) : null,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _SettingsTileText(title: title, subtitle: subtitle),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: const Color(0xFF9CC4FF),
            activeTrackColor: const Color(0x806EA8FF),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    ),
  );
}

class _SettingsChoiceTile extends StatelessWidget {
  const _SettingsChoiceTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    selected: selected,
    onTap: onTap,
    child: Row(
      children: <Widget>[
        Expanded(
          child: _SettingsTileText(title: title, subtitle: subtitle),
        ),
        const SizedBox(width: 14),
        _SelectionMark(selected),
      ],
    ),
  );
}

class _SettingsSliderTile extends StatelessWidget {
  const _SettingsSliderTile({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _SettingsTileText(title: title, subtitle: subtitle),
            ),
            const SizedBox(width: 12),
            Text(
              valueLabel,
              style: const TextStyle(
                color: Color(0xFF9CC4FF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
          activeColor: const Color(0xFF6EA8FF),
          inactiveColor: const Color(0x28FFFFFF),
        ),
      ],
    ),
  );
}

class _SettingsStatusCard extends StatelessWidget {
  const _SettingsStatusCard({
    required this.title,
    required this.value,
    required this.description,
  });

  final String title;
  final String value;
  final String description;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (description.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 7),
          Text(
            description,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ],
    ),
  );
}

class _SettingsTileText extends StatelessWidget {
  const _SettingsTileText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (subtitle.trim().isNotEmpty) ...<Widget>[
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            height: 1.35,
          ),
        ),
      ],
    ],
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child, this.onTap, this.selected = false});

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0x246EA8FF) : const Color(0x121F2A3A),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? const Color(0x806EA8FF) : const Color(0x0FFFFFFF),
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      hoverColor: const Color(0x1AFFFFFF),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: child,
      ),
    ),
  );
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.time,
    required this.note,
    required this.onTap,
    required this.onDelete,
  });

  final String time;
  final String note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => _SettingsCard(
    onTap: onTap,
    child: Row(
      children: <Widget>[
        const Icon(Icons.bookmark_rounded, color: Color(0xFF9CC4FF)),
        const SizedBox(width: 13),
        Expanded(
          child: _SettingsTileText(
            title: time,
            subtitle: note.trim().isEmpty ? '点击跳转到此时间点' : note,
          ),
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).commonDelete,
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded, size: 19),
          color: Colors.white54,
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _PanelScroll extends StatelessWidget {
  const _PanelScroll({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext c) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.title, this.subtitle);
  final String title, subtitle;
  @override
  Widget build(BuildContext c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (subtitle.trim().isNotEmpty)
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
    ],
  );
}

class _OptionCard extends StatelessWidget {
  const _OptionCard(
    this.title, {
    this.subtitle = '',
    this.icon,
    this.selected = false,
    this.onTap,
  });
  final String title, subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext c) => Material(
    color: selected ? const Color(0x2463A0FF) : const Color(0x121F2A3A),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: selected ? const Color(0x8063A0FF) : const Color(0x0FFFFFFF),
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onTap == null ? Colors.white38 : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0x73FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            _SelectionMark(selected),
          ],
        ),
      ),
    ),
  );
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark(this.selected);
  final bool selected;
  @override
  Widget build(BuildContext c) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? const Color(0xFF63A0FF) : Colors.transparent,
      border: Border.all(
        color: selected ? const Color(0xFF63A0FF) : Colors.white38,
        width: 1.5,
      ),
    ),
    child: selected
        ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
        : null,
  );
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel(this.label);
  final String label;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(
      child: Text(label, style: const TextStyle(color: Colors.white54)),
    ),
  );
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle(this.icon, this.selected, this.onTap);
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) => IconButton(
    icon: Icon(icon, size: 18),
    color: selected ? Colors.white : Colors.white38,
    tooltip: selected ? '当前视图' : '切换视图',
    onPressed: onTap,
    style: IconButton.styleFrom(
      fixedSize: const Size.square(34),
      padding: EdgeInsets.zero,
      backgroundColor: selected ? const Color(0x246EA8FF) : Colors.transparent,
      hoverColor: const Color(0x1AFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
  );
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard(
    this.episode,
    this.current,
    this.enabled,
    this.grid,
    this.onTap,
  );
  final Map<String, dynamic> episode;
  final bool current, enabled, grid;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext c) {
    final shortLabel = '${episode['shortLabel'] ?? ''}'.trim();
    final episodeNumber = '${episode['episodeNumber'] ?? ''}'.trim();
    final numberLabel = shortLabel.isNotEmpty
        ? shortLabel
        : (episodeNumber.isNotEmpty ? episodeNumber : '—');
    final rawTitle = '${episode['title'] ?? ''}'.trim();
    final title = rawTitle.isNotEmpty ? rawTitle : '第$numberLabel集';
    final poster = '${episode['poster'] ?? episode['posterPath'] ?? ''}'.trim();
    final headers = _stringMap(episode['imageHeaders']);
    final watched = episode['watched'] == true || episode['watched'] == 1,
        downloaded =
            episode['downloaded'] == true || episode['downloaded'] == 1;
    final duration = int.tryParse('${episode['duration'] ?? 0}') ?? 0;
    final watchedSeconds =
        int.tryParse(
          '${episode['ts'] ?? episode['watchedTs'] ?? episode['watchedSeconds'] ?? episode['playedSeconds'] ?? 0}',
        ) ??
        0;
    final progress = duration > 0
        ? (watchedSeconds / duration).clamp(0, 1).toDouble()
        : 0.0;
    final image = _EpisodePoster(
      poster,
      grid,
      headers: headers,
      current: current,
    );
    final content = grid
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: image),
              const SizedBox(height: 7),
              Text(
                '第$numberLabel集 · $title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (progress > 0)
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  color: const Color(0xFF63A0FF),
                  backgroundColor: Colors.white12,
                ),
            ],
          )
        : Row(
            children: [
              image,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '第$numberLabel集 · $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (duration > 0)
                      Text(
                        _duration(duration),
                        style: const TextStyle(
                          color: Color(0x73FFFFFF),
                          fontSize: 11,
                        ),
                      ),
                    if (progress > 0)
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        color: const Color(0xFF63A0FF),
                        backgroundColor: Colors.white12,
                      ),
                  ],
                ),
              ),
              if (watched)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF63A0FF),
                  size: 17,
                ),
              if (downloaded)
                const Icon(
                  Icons.download_done_rounded,
                  color: Colors.white54,
                  size: 17,
                ),
            ],
          );
    return Opacity(
      opacity: enabled || current ? 1 : .5,
      child: Material(
        color: current ? const Color(0x2463A0FF) : const Color(0x121F2A3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: current ? const Color(0x8063A0FF) : const Color(0x0FFFFFFF),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(10), child: content),
        ),
      ),
    );
  }

  Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  String _duration(int s) =>
      '${s ~/ 3600 > 0 ? '${s ~/ 3600}:' : ''}${(s ~/ 60 % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

class _EpisodePoster extends StatelessWidget {
  const _EpisodePoster(
    this.path,
    this.grid, {
    required this.headers,
    required this.current,
  });
  final String path;
  final bool grid;
  final Map<String, String> headers;
  final bool current;
  @override
  Widget build(BuildContext c) {
    final uri = Uri.tryParse(path);
    final image = path.startsWith('http://') || path.startsWith('https://')
        ? Image.network(
            path,
            headers: headers,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
          )
        : path.isNotEmpty
        ? Image.file(
            File(uri?.scheme == 'file' ? uri!.toFilePath(windows: true) : path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
          )
        : _placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: grid ? double.infinity : 112,
        height: grid ? double.infinity : 64,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (current)
              const ColoredBox(
                color: Color(0x42000000),
                child: Center(child: _NowPlayingIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => const ColoredBox(
    color: Color(0x241F2A3A),
    child: Center(child: Icon(Icons.movie_outlined, color: Colors.white30)),
  );
}

class _NowPlayingIndicator extends StatefulWidget {
  const _NowPlayingIndicator();

  @override
  State<_NowPlayingIndicator> createState() => _NowPlayingIndicatorState();
}

class _NowPlayingIndicatorState extends State<_NowPlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(5, (index) {
          final phase = (_controller.value + index * .17) % 1;
          final height = 6 + (phase < .5 ? phase : 1 - phase) * 24;
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Color(0xFF6EA8FF)],
              ),
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ),
    );
  }
}
