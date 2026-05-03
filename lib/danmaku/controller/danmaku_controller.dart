import 'dart:async';

import 'package:flutter/material.dart';

import '../models/danmaku_comment.dart';
import '../models/danmaku_settings.dart';
import '../settings/danmaku_settings_store.dart';

enum DanmakuLoadedSourceType { none, local, network }

class DanmakuController extends ChangeNotifier {
  final DanmakuSettingsStore _store;
  Timer? _saveSettingsTimer;

  DanmakuController(this._store);

  DanmakuSettings _settings = DanmakuSettings.defaults;
  List<DanmakuComment> _comments = const <DanmakuComment>[];
  bool _ready = false;
  bool _supportsAutoMatch = false;
  String _currentTitle = '';
  String _currentSeasonGuid = '';
  String _sourceLabel = '';
  int _seasonNumber = 0;
  int _episodeNumber = 0;
  DanmakuLoadedSourceType _loadedSourceType = DanmakuLoadedSourceType.none;

  DanmakuSettings get settings => _settings;
  List<DanmakuComment> get comments => _comments;
  bool get ready => _ready;
  bool get supportsAutoMatch => _supportsAutoMatch;
  String get manualSourceLabel => _sourceLabel;
  DanmakuLoadedSourceType get loadedSourceType => _loadedSourceType;

  String get statusLabel {
    if (!_settings.enabled) return 'Off';
    return switch (_loadedSourceType) {
      DanmakuLoadedSourceType.local => 'Local',
      DanmakuLoadedSourceType.network => 'DanDanPlay',
      DanmakuLoadedSourceType.none => 'Not loaded',
    };
  }

  String get summaryText {
    if (!_settings.enabled) {
      return 'Danmaku is disabled.';
    }
    if (_comments.isNotEmpty) {
      final sourcePrefix = switch (_loadedSourceType) {
        DanmakuLoadedSourceType.local => 'Local danmaku loaded',
        DanmakuLoadedSourceType.network => 'DanDanPlay danmaku loaded',
        DanmakuLoadedSourceType.none => 'Danmaku loaded',
      };
      final label = _sourceLabel.trim();
      if (label.isNotEmpty) {
        return '$sourcePrefix: $label, ${_comments.length} items.';
      }
      return '$sourcePrefix, ${_comments.length} items.';
    }
    if (_supportsAutoMatch) {
      return 'No danmaku loaded. Search DanDanPlay or import a local file.';
    }
    final title = _currentEpisodeContextLabel();
    if (title.isNotEmpty) {
      return '$title has no danmaku loaded. Import a local file.';
    }
    return 'No danmaku loaded for this source. Import a local file.';
  }

  Future<void> initialize() async {
    _settings = await _store.load();
    _ready = true;
    notifyListeners();
  }

  Future<void> updateSettings(DanmakuSettings next) async {
    _settings = next;
    notifyListeners();
    _saveSettingsTimer?.cancel();
    _saveSettingsTimer = Timer(const Duration(milliseconds: 160), () {
      _saveSettingsTimer = null;
      unawaited(_store.save(_settings));
    });
  }

  void updateMediaContext({
    required String title,
    required String seasonGuid,
    required int seasonNumber,
    required int episodeNumber,
  }) {
    final nextTitle = title.trim();
    final nextSeasonGuid = seasonGuid.trim();
    final nextSupportsAutoMatch =
        nextSeasonGuid.isNotEmpty || episodeNumber > 0 || seasonNumber > 0;
    final contextChanged =
        _currentTitle != nextTitle ||
        _currentSeasonGuid != nextSeasonGuid ||
        _seasonNumber != seasonNumber ||
        _episodeNumber != episodeNumber;
    final metadataChanged =
        _supportsAutoMatch != nextSupportsAutoMatch || contextChanged;
    _currentTitle = nextTitle;
    _currentSeasonGuid = nextSeasonGuid;
    _supportsAutoMatch = nextSupportsAutoMatch;
    _seasonNumber = seasonNumber;
    _episodeNumber = episodeNumber;
    if (!contextChanged) {
      if (metadataChanged) {
        notifyListeners();
      }
      return;
    }
    _sourceLabel = '';
    _loadedSourceType = DanmakuLoadedSourceType.none;
    _comments = const <DanmakuComment>[];
    notifyListeners();
  }

  void setComments(List<DanmakuComment> comments) {
    _sourceLabel = '';
    _loadedSourceType = DanmakuLoadedSourceType.none;
    _comments = _normalizeComments(comments);
    notifyListeners();
  }

  void applyImportedComments({
    required String sourceLabel,
    required DanmakuLoadedSourceType sourceType,
    required List<DanmakuComment> comments,
  }) {
    _sourceLabel = sourceLabel.trim();
    _loadedSourceType = sourceType;
    _comments = _normalizeComments(comments);
    notifyListeners();
  }

  List<DanmakuComment> _normalizeComments(List<DanmakuComment> comments) {
    final normalized =
        comments
            .where((item) => item.text.trim().isNotEmpty)
            .toList(growable: false)
          ..sort((left, right) {
            final timeCompare = left.timeMs.compareTo(right.timeMs);
            if (timeCompare != 0) return timeCompare;
            return left.id.compareTo(right.id);
          });
    return List<DanmakuComment>.unmodifiable(normalized);
  }

  String _currentEpisodeContextLabel() {
    final title = _currentTitle.trim();
    final parts = <String>[
      if (title.isNotEmpty) title,
      if (_seasonNumber > 0) 'Season $_seasonNumber',
      if (_episodeNumber > 0) 'Episode $_episodeNumber',
    ];
    return parts.join(' ');
  }

  @override
  void dispose() {
    final pendingSave = _saveSettingsTimer;
    _saveSettingsTimer = null;
    pendingSave?.cancel();
    unawaited(_store.save(_settings));
    super.dispose();
  }
}
