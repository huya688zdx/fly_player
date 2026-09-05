import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/detail/media_episode_summary.dart';
import 'package:fly_player/media_backend/detail/media_season_summary.dart';
import 'package:fly_player/media_backend/media_backend.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/services/server_native_picker_support.dart';

/// 只实现选集所需的两个查询；其余接口方法抛错（本测不触达）。
class _FakePickerBackend implements MediaBackend {
  _FakePickerBackend({
    this.seasons = const [],
    this.episodesBySeason = const {},
  });

  final List<MediaSeasonSummary> seasons;
  final Map<String, List<MediaEpisodeSummary>> episodesBySeason;
  final List<String> seasonCalls = <String>[];
  final List<String> episodeCalls = <String>[];

  @override
  Future<List<MediaSeasonSummary>> getItemSeasons(String seriesId) async {
    seasonCalls.add(seriesId);
    return seasons;
  }

  @override
  Future<List<MediaEpisodeSummary>> getSeasonEpisodes(String seasonId) async {
    episodeCalls.add(seasonId);
    return episodesBySeason[seasonId] ?? const <MediaEpisodeSummary>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 未在测试桩实现');
}

MediaSeasonSummary _season(String id, int number) => MediaSeasonSummary(
  id: id,
  title: '',
  seasonNumber: number,
  primaryImage: MediaImageRef.empty,
);

MediaEpisodeSummary _episode(String id, int number, {bool watched = false}) =>
    MediaEpisodeSummary(
      id: id,
      title: '第$number集',
      seasonNumber: 1,
      episodeNumber: number,
      primaryImage: MediaImageRef(url: 'https://emby.test/$id.jpg'),
      durationSeconds: 1500,
      watched: watched,
      resumePositionSeconds: number * 10,
    );

String _loadArgs({
  String seriesGuid = 'series-1',
  String seasonGuid = 'season-1',
}) {
  return jsonEncode(<String, dynamic>{
    'seriesGuid': seriesGuid,
    'seasonGuid': seasonGuid,
    'seriesTitle': '某剧',
    'itemGuid': 'ep-1',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loadEpisodePickerData：季列表 + 当前季剧集 + 选中季标记', () async {
    final backend = _FakePickerBackend(
      seasons: <MediaSeasonSummary>[
        _season('season-1', 1),
        _season('season-2', 2),
      ],
      episodesBySeason: <String, List<MediaEpisodeSummary>>{
        'season-1': <MediaEpisodeSummary>[
          _episode('ep-1', 1, watched: true),
          _episode('ep-2', 2),
        ],
      },
    );
    final data = await ServerNativePickerSupport.loadEpisodePickerData(
      backend,
      l10n: l10n,
      currentLoadArgs: _loadArgs(),
    );
    expect(data, isNotNull);
    expect(data!['selectedSeasonGuid'], 'season-1');
    expect(data['viewType'], 'card');
    expect(data['seriesTitle'], '某剧');
    final seasons = data['seasons'] as List;
    expect(seasons.length, 2);
    expect((seasons.first as Map)['seasonLabel'], '第1季');
    expect((seasons.first as Map)['selected'], isTrue);
    expect((seasons[1] as Map)['selected'], isFalse);
    final episodes = data['episodes'] as List;
    expect(episodes.length, 2);
    final first = episodes.first as Map;
    expect(first['itemGuid'], 'ep-1');
    expect(first['seasonGuid'], 'season-1');
    expect(first['watched'], 1);
    expect(first['duration'], 1500);
    expect(first['imageAuth'], '');
    expect(first['imageHeaders'], isEmpty);
    expect(first['poster'], 'https://emby.test/ep-1.jpg');
  });

  test('loadEpisodePickerData：请求季优先于当前季', () async {
    final backend = _FakePickerBackend(
      seasons: <MediaSeasonSummary>[
        _season('season-1', 1),
        _season('season-2', 2),
      ],
      episodesBySeason: <String, List<MediaEpisodeSummary>>{
        'season-2': <MediaEpisodeSummary>[_episode('ep-9', 9)],
      },
    );
    final data = await ServerNativePickerSupport.loadEpisodePickerData(
      backend,
      l10n: l10n,
      currentLoadArgs: _loadArgs(),
      seasonGuid: 'season-2',
    );
    expect(data!['selectedSeasonGuid'], 'season-2');
    expect(backend.episodeCalls, contains('season-2'));
    expect((data['episodes'] as List).single, isA<Map>());
  });

  test('loadEpisodePickerData：季列表取数失败退化为当前季 fallback', () async {
    final backend = _FakePickerBackend(
      episodesBySeason: const <String, List<MediaEpisodeSummary>>{},
    );
    final fallback = <Map<String, dynamic>>[
      <String, dynamic>{'itemGuid': 'ep-1', 'seasonGuid': 'season-1'},
    ];
    final data = await ServerNativePickerSupport.loadEpisodePickerData(
      backend,
      l10n: l10n,
      currentLoadArgs: _loadArgs(),
      fallbackEpisodes: fallback,
    );
    expect(data, isNotNull);
    // 无季列表、该季无剧集 → 回退到静态 fallback。
    expect((data!['episodes'] as List).length, 1);
    expect(((data['episodes'] as List).first as Map)['itemGuid'], 'ep-1');
  });

  test('loadEpisodePickerData：空 loadArgs 返回 null', () async {
    final backend = _FakePickerBackend();
    expect(
      await ServerNativePickerSupport.loadEpisodePickerData(
        backend,
        l10n: l10n,
        currentLoadArgs: '',
      ),
      isNull,
    );
  });

  test('loadSeasonEpisodes：指定季剧集；空季返回 null', () async {
    final backend = _FakePickerBackend(
      episodesBySeason: <String, List<MediaEpisodeSummary>>{
        'season-2': <MediaEpisodeSummary>[_episode('ep-9', 9)],
      },
    );
    final data = await ServerNativePickerSupport.loadSeasonEpisodes(
      backend,
      seasonGuid: 'season-2',
    );
    expect(data!['seasonGuid'], 'season-2');
    expect((data['episodes'] as List).length, 1);
    expect(
      await ServerNativePickerSupport.loadSeasonEpisodes(
        backend,
        seasonGuid: 'season-empty',
      ),
      isNull,
    );
  });

  test('setEpisodePickerViewType：合法值持久化、非法值拒绝', () async {
    expect(
      await ServerNativePickerSupport.setEpisodePickerViewType('button'),
      isTrue,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('playlist_view_type'), 'button');
    expect(
      await ServerNativePickerSupport.setEpisodePickerViewType('bogus'),
      isFalse,
    );
    // 持久化后 loadEpisodePickerData 回读该偏好。
    final backend = _FakePickerBackend();
    final data = await ServerNativePickerSupport.loadEpisodePickerData(
      backend,
      l10n: l10n,
      currentLoadArgs: _loadArgs(),
    );
    expect(data!['viewType'], 'button');
  });
}
