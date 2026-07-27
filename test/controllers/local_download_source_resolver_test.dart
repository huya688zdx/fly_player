import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/api/person_list_request.dart';
import 'package:fly_player/controllers/local_download_source_resolver.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_detail_data_gateway.dart';
import 'package:fly_player/models/download_task_record.dart';
import 'package:fly_player/models/media_library_item.dart';
import 'package:fly_player/models/person_credit.dart';
import 'package:fly_player/models/play_info.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/services/app_log_service.dart';

/// 三个回放元数据接口全部抛错的 fake gateway，用于锁定降级路径。
class _ThrowingGateway implements FeiniuDetailDataGateway {
  int playInfoCalls = 0;
  int trackDataCalls = 0;
  int playbackStreamCalls = 0;

  @override
  Future<PlayInfoData> getPlayInfo(String itemGuid) async {
    playInfoCalls++;
    throw StateError('play info unavailable');
  }

  @override
  Future<StreamTrackData> getStreamTrackData(String itemGuid) async {
    trackDataCalls++;
    throw StateError('stream track unavailable');
  }

  @override
  Future<PlaybackStreamData> getPlaybackStream(String mediaGuid) async {
    playbackStreamCalls++;
    throw StateError('playback stream unavailable');
  }

  @override
  Future<Map<String, dynamic>> getItemDetail(String itemGuid) =>
      throw UnimplementedError();

  @override
  Future<List<PersonCredit>> getPersonList(
    String itemGuid, {
    required PersonListRequest request,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> getDownloadResolutionOptions(
    String playItemGuid, {
    required String lan,
  }) => throw UnimplementedError();

  @override
  Future<List<MediaLibraryItem>> getEpisodeList(String seasonGuid) =>
      throw UnimplementedError();
}

DownloadTaskRecord _record({
  required String filePath,
  required String itemGuid,
  required String mediaGuid,
}) {
  return DownloadTaskRecord(
    id: 'record-1',
    remoteTaskId: '',
    itemGuid: itemGuid,
    mediaGuid: mediaGuid,
    groupId: 'group-1',
    groupTitle: 'GroupTitle',
    title: 'RecTitle',
    durationText: '',
    posterUrls: const <String>['http://nas.local/poster.jpg'],
    groupPosterUrls: const <String>[],
    resolution: '1080p',
    fileName: 'video.mkv',
    filePath: filePath,
    totalBytes: 0,
    downloadedBytes: 0,
    audioTracks: const <AudioTrackOption>[
      AudioTrackOption(
        mediaGuid: 'media-x',
        guid: 'aud-1',
        title: 'A1',
        codecName: 'aac',
        profile: '',
        language: 'zh',
        audioType: '',
        channelLayout: 'stereo',
        channels: 2,
        sampleRate: 48000,
        bps: 128000,
        index: 0,
        isDefault: 1,
      ),
    ],
    status: DownloadTaskStatus.downloaded,
    errorMessage: '',
    createdAtMs: 0,
    updatedAtMs: 0,
    tmdbId: 'tm123',
    seasonNumber: 2,
    episodeNumber: 5,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('zh'));
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = Directory.systemTemp.createTempSync('local_dl_resolver_test');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('本地文件不存在时返回 null 且不触碰 gateway', () async {
    final gateway = _ThrowingGateway();
    final record = _record(
      filePath: '${tempDir.path}${Platform.pathSeparator}missing.mkv',
      itemGuid: 'itm-a',
      mediaGuid: 'med-a',
    );

    final result = await resolveLocalDownloadSource(
      record,
      gateway,
      l10n: l10n,
    );

    expect(result, isNull);
    expect(gateway.playInfoCalls, 0);
    expect(gateway.trackDataCalls, 0);
    expect(gateway.playbackStreamCalls, 0);
  });

  test('三条网络元数据全失败时降级到下载记录字段,并留痕 logSwallowedError', () async {
    final token = 'tk${DateTime.now().microsecondsSinceEpoch}';
    final itemGuid = 'itm-$token';
    final mediaGuid = 'med-$token';
    final file = File('${tempDir.path}${Platform.pathSeparator}video.mkv')
      ..writeAsBytesSync(const <int>[0, 1, 2, 3]);
    final gateway = _ThrowingGateway();
    final record = _record(
      filePath: file.path,
      itemGuid: itemGuid,
      mediaGuid: mediaGuid,
    );

    final result = await resolveLocalDownloadSource(
      record,
      gateway,
      l10n: l10n,
    );

    // 三条请求各发起一次,失败不阻塞播放。
    expect(gateway.playInfoCalls, 1);
    expect(gateway.trackDataCalls, 1);
    expect(gateway.playbackStreamCalls, 1);

    // 降级路径:全部字段来自下载记录 fallback。
    expect(result, isNotNull);
    final source = result!.source;
    expect(result.playInfo, isNull);
    expect(result.title, 'GroupTitle RecTitle');
    expect(source.url, Uri.file(file.path).toString());
    expect(source.itemGuid, itemGuid);
    expect(source.mediaGuid, mediaGuid);
    expect(source.posterPath, 'http://nas.local/poster.jpg');
    expect(source.resolution, '1080p');
    expect(source.audioTracks, hasLength(1));
    expect(source.audioTrackGuid, 'aud-1');
    expect(source.startPosition, Duration.zero);
    // 离线弹幕兜底字段透传自记录。
    expect(source.tmdbId, 'tm123');
    expect(source.seasonNumber, 2);
    expect(source.episodeNumber, 5);

    // logSwallowedError 行为锁定:三条降级各留一条 warning,来源与 action 固定。
    await pumpEventQueue();
    final swallowed = AppLogService.instance.entries
        .where(
          (entry) =>
              entry.source == 'local_download_source_resolver' &&
              (entry.details ?? '').contains(token),
        )
        .toList(growable: false);
    expect(swallowed, hasLength(3));
    expect(
      swallowed.every((entry) => entry.level == AppLogLevel.warning),
      isTrue,
    );
    final details = swallowed.map((entry) => entry.details ?? '').join('\n');
    expect(details, contains('action=resolve local download play info'));
    expect(details, contains('action=resolve local download stream tracks'));
    expect(details, contains('action=resolve local download playback stream'));
    expect(details, contains('id=$itemGuid'));
    expect(details, contains('id=$mediaGuid'));
  });
}
