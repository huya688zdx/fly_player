import 'dart:async';

import 'package:flutter/material.dart';

import '../models/danmaku_comment.dart';
import '../models/danmaku_settings.dart';
import '../settings/danmaku_settings_store.dart';

enum DanmakuLoadedSourceType { none, local, network }

class DanmakuController extends ChangeNotifier {
  final DanmakuSettingsStore _store;

  DanmakuController(this._store);

  DanmakuSettings _settings = DanmakuSettings.defaults;
  List<DanmakuComment> _comments = const <DanmakuComment>[];
  bool _ready = false;
  bool _supportsAutoMatch = false;
  String _currentTitle = '';
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
    if (!_settings.enabled) return '已关闭';
    return switch (_loadedSourceType) {
      DanmakuLoadedSourceType.local => '本地',
      DanmakuLoadedSourceType.network => '弹弹play',
      DanmakuLoadedSourceType.none => '未载入',
    };
  }

  String get summaryText {
    if (!_settings.enabled) {
      return '弹幕层已关闭，开启后会按当前优先级自动载入弹幕。';
    }
    if (_comments.isNotEmpty) {
      final sourcePrefix = switch (_loadedSourceType) {
        DanmakuLoadedSourceType.local => '当前已加载本地弹幕',
        DanmakuLoadedSourceType.network => '当前已加载弹弹play弹幕',
        DanmakuLoadedSourceType.none => '当前已加载弹幕',
      };
      final label = _sourceLabel.trim();
      if (label.isNotEmpty) {
        return '$sourcePrefix：$label，共 ${_comments.length} 条。';
      }
      return '$sourcePrefix，共 ${_comments.length} 条。';
    }
    if (_supportsAutoMatch) {
      return '当前还没有载入弹幕，可搜索弹弹play弹幕或手动导入本地弹幕。';
    }
    final title = _currentEpisodeContextLabel();
    if (title.isNotEmpty) {
      return '$title 暂未载入弹幕，可手动导入本地弹幕。';
    }
    return '当前片源暂未载入弹幕，可手动导入本地弹幕。';
  }

  Future<void> initialize() async {
    _settings = await _store.load();
    _ready = true;
    notifyListeners();
  }

  Future<void> updateSettings(DanmakuSettings next) async {
    _settings = next;
    notifyListeners();
    unawaited(_store.save(next));
  }

  void updateMediaContext({
    required String title,
    required String seasonGuid,
    required int seasonNumber,
    required int episodeNumber,
  }) {
    _currentTitle = title.trim();
    _sourceLabel = '';
    _loadedSourceType = DanmakuLoadedSourceType.none;
    _supportsAutoMatch =
        seasonGuid.trim().isNotEmpty || episodeNumber > 0 || seasonNumber > 0;
    _seasonNumber = seasonNumber;
    _episodeNumber = episodeNumber;
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
    final normalized = comments
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
      if (_seasonNumber > 0) '第$_seasonNumber季',
      if (_episodeNumber > 0) '第$_episodeNumber集',
    ];
    return parts.join(' ');
  }
}
