import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/api/person_list_request.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_play_stats_gateway.dart';
import 'package:fly_player/models/person_credit.dart';
import 'package:fly_player/services/play_stats/play_stats_backfill_service.dart';
import 'package:fly_player/services/play_stats/play_stats_database.dart';
import 'package:fly_player/services/play_stats/play_stats_metadata_gateway.dart';
import 'package:fly_player/services/play_stats/play_stats_models.dart';
import 'package:fly_player/services/play_stats/play_stats_repositories.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  group('回填判型只认 type == movie', () {
    // 两个用例喂完全相同的详情载荷，只有 type 不同：能观察到的差异就只可能来自判型。
    Map<String, dynamic> itemDetail(String type) => <String, dynamic>{
      'type': type,
      'title': '第 1 集',
      'tv_title': '示例剧集',
      'parent_guid': 'season-1',
      'genres': <int>[7],
      'production_countries': <String>['cn'],
      'release_date': '2019-04-05',
    };

    // 季度详情自带完整题材/地区，避免触发"再往上追一层剧集详情"的补齐分支，
    // 让请求序列只反映判型差异。
    const seasonDetail = <String, dynamic>{
      'title': '第一季',
      'parent_guid': 'anime-1',
      'genres': <int>[7],
      'production_countries': <String>['CN'],
    };

    test('非电影：按 parent_guid 追查季度详情，并落季度标题', () async {
      final gateway = _FakeBackfillGateway(<String, Map<String, dynamic>>{
        'video-1': itemDetail('episode'),
        'season-1': seasonDetail,
      });
      final harness = _Harness(gateway);

      await harness.run();

      expect(gateway.detailRequests, <String>['video-1', 'season-1']);
      expect(harness.videoStatsValues['video_kind'], 'episode');
      expect(harness.videoStatsValues['season_title'], '第一季');
    });

    test('电影：不追查季度详情，题材/地区直接取条目自身', () async {
      final gateway = _FakeBackfillGateway(<String, Map<String, dynamic>>{
        'video-1': itemDetail('movie'),
        'season-1': seasonDetail,
      });
      final harness = _Harness(gateway);

      await harness.run();

      expect(gateway.detailRequests, <String>['video-1']);
      expect(harness.videoStatsValues['video_kind'], 'movie');
      // 地区码统一大写、年份只抠四位数字，二者都来自条目自身而非季度。
      expect(
        jsonDecode(harness.videoStatsValues['country_codes_json'] as String),
        <String>['CN'],
      );
      expect(harness.videoStatsValues['year'], 2019);
    });

    test('判型忽略大小写与空白', () async {
      final gateway = _FakeBackfillGateway(<String, Map<String, dynamic>>{
        'video-1': itemDetail('  MOVIE '),
        'season-1': seasonDetail,
      });
      final harness = _Harness(gateway);

      await harness.run();

      expect(gateway.detailRequests, <String>['video-1']);
    });
  });

  group('演职员映射语义收在飞牛网关实现侧', () {
    test('过滤空 personGuid、job 转小写、按 personGuid 去空白', () async {
      final gateway = FeiniuPlayStatsGateway(
        _FakeFeiniuApi(<PersonCredit>[
          _credit(personGuid: ' p-1 ', name: '甲', job: 'Director', order: 1),
          // personGuid 为空的条目落库后无法回指人物，必须在网关侧就丢掉。
          _credit(personGuid: '   ', name: '乙', job: 'Actor', order: 2),
          _credit(personGuid: 'p-2', name: '丙', job: 'ACTOR', order: 3),
        ]),
      );

      final credits = await gateway.fetchCredits('video-1');

      expect(credits.map((credit) => credit.personId), <String>['p-1', 'p-2']);
      expect(credits.map((credit) => credit.job), <String>[
        'director',
        'actor',
      ]);
    });

    test('回填服务本身不再做映射，直接采信网关给出的信用列表', () async {
      final gateway = _FakeBackfillGateway(
        <String, Map<String, dynamic>>{
          'video-1': <String, dynamic>{'type': 'movie', 'title': '电影'},
        },
        credits: const <PlayStatsCredit>[
          // 空 personId 在服务侧只影响 video_credits 落库，不做二次清洗。
          PlayStatsCredit(
            personId: 'p-1',
            name: '甲',
            role: '',
            job: 'Director',
            order: 1,
          ),
        ],
      );
      final harness = _Harness(gateway);

      await harness.run();

      expect(gateway.creditRequests, <String>['video-1']);
      final stored =
          jsonDecode(harness.videoStatsValues['credits_json'] as String)
              as List<dynamic>;
      expect(stored, hasLength(1));
      // 原样透传：服务侧不再重复做小写化之类的清洗。
      expect((stored.first as Map<String, dynamic>)['job'], 'Director');
    });
  });
}

PersonCredit _credit({
  required String personGuid,
  required String name,
  required String job,
  required int order,
}) {
  return PersonCredit(
    itemGuid: 'video-1',
    personGuid: personGuid,
    role: '',
    job: job,
    order: order,
    name: name,
    originalName: '',
    profilePath: '',
  );
}

/// 把回填服务连同假数据库、假仓储装好，跑一轮回填并暴露写回的字段。
class _Harness {
  _Harness(this._gateway)
    : _database = _FakeDatabase(),
      _videoStatsRepository = _FakeVideoStatsRepository(_existingRecord),
      _videoCreditStatsRepository = _FakeVideoCreditStatsRepository();

  static const VideoStatsRecord _existingRecord = VideoStatsRecord(
    videoId: 'video-1',
    animeId: '',
    seasonId: '',
    title: '',
    animeTitle: '',
    seasonTitle: '',
    videoKind: '',
    countsTowardCompletion: true,
    country: 'CN',
    countryCodes: <String>['CN'],
    genreIds: <int>[7],
    year: 2019,
    mediaDurationMs: 0,
    clickCount: 0,
    autoPlayCount: 0,
    viewCount: 1,
    totalPlayedMs: 0,
    maxProgress: 0,
    lastProgress: 0,
    lastPositionMs: 0,
    completed: false,
    metadataEnriched: false,
    lastPlayedAtMs: 0,
    credits: <PlayStatsCredit>[],
  );

  final PlayStatsBackfillGateway _gateway;
  final _FakeDatabase _database;
  final _FakeVideoStatsRepository _videoStatsRepository;
  final _FakeVideoCreditStatsRepository _videoCreditStatsRepository;

  Map<String, Object?> get videoStatsValues =>
      _database.executor.updates['video_stats'] ?? const <String, Object?>{};

  Future<void> run() {
    final service = PlayStatsMetadataBackfillService(
      database: _database,
      videoStatsRepository: _videoStatsRepository,
      videoCreditStatsRepository: _videoCreditStatsRepository,
    );
    return service.backfillNow(
      gateway: _gateway,
      preferredVideoIds: const <String>['video-1'],
    );
  }
}

class _FakeBackfillGateway implements PlayStatsBackfillGateway {
  _FakeBackfillGateway(
    this._details, {
    this.credits = const <PlayStatsCredit>[],
  });

  final Map<String, Map<String, dynamic>> _details;
  final List<PlayStatsCredit> credits;
  final List<String> detailRequests = <String>[];
  final List<String> creditRequests = <String>[];

  @override
  Future<Map<String, dynamic>> fetchItemDetail(String itemId) async {
    detailRequests.add(itemId);
    final detail = _details[itemId];
    if (detail == null) {
      throw StateError('未准备 $itemId 的详情');
    }
    return detail;
  }

  @override
  Future<List<PlayStatsCredit>> fetchCredits(String itemId) async {
    creditRequests.add(itemId);
    return credits;
  }
}

class _FakeFeiniuApi implements FeiniuApi {
  _FakeFeiniuApi(this._credits);

  final List<PersonCredit> _credits;

  @override
  Future<List<PersonCredit>> getPersonList(
    String itemGuid, {
    PersonListRequest request = const PersonListRequest(),
  }) async {
    return _credits;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDatabase implements PlayStatsDatabase {
  final _FakeExecutor executor = _FakeExecutor();

  @override
  Future<T> transaction<T>(Future<T> Function(DatabaseExecutor txn) action) {
    return action(executor);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeExecutor implements DatabaseExecutor {
  final Map<String, Map<String, Object?>> updates =
      <String, Map<String, Object?>>{};

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    updates[table] = values;
    return 1;
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    return 1;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    return Future<int>.value(0);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    return const <Map<String, Object?>>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVideoStatsRepository implements VideoStatsRepository {
  _FakeVideoStatsRepository(this._record);

  final VideoStatsRecord _record;

  @override
  Future<VideoStatsRecord?> getByVideoId(
    String videoId, {
    DatabaseExecutor? executor,
  }) async {
    return videoId == _record.videoId ? _record : null;
  }

  @override
  Future<List<String>> listMetadataBackfillCandidateIds({
    int limit = 20,
    DatabaseExecutor? executor,
  }) async {
    return const <String>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVideoCreditStatsRepository implements VideoCreditStatsRepository {
  final List<VideoCreditRecord> replaced = <VideoCreditRecord>[];

  @override
  Future<void> replaceForVideo(
    String videoId,
    List<VideoCreditRecord> records, {
    DatabaseExecutor? executor,
  }) async {
    replaced
      ..clear()
      ..addAll(records);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
