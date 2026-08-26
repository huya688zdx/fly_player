import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/models/download_task_record.dart';
import 'package:fly_player/models/stream_list_option.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/services/download_task_service.dart';

void main() {
  test('DownloadTaskRecord round-trips audio and subtitle tracks', () {
    const record = DownloadTaskRecord(
      id: 'record-1',
      remoteTaskId: 'remote-1',
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      groupId: 'group-1',
      groupTitle: 'Group',
      title: 'Title',
      durationText: '24m',
      posterUrls: <String>['poster'],
      groupPosterUrls: <String>['groupPoster'],
      resolution: '1080p',
      fileName: 'demo.mkv',
      filePath: '/tmp/demo.mkv',
      totalBytes: 1024,
      downloadedBytes: 1024,
      audioTracks: <AudioTrackOption>[
        AudioTrackOption(
          mediaGuid: 'media-1',
          guid: 'audio-1',
          title: 'Japanese 2.0',
          codecName: 'aac',
          profile: '',
          language: 'jpn',
          audioType: '',
          channelLayout: 'stereo',
          channels: 2,
          sampleRate: 48000,
          bps: 128000,
          index: 1,
          isDefault: 1,
        ),
      ],
      subtitleTracks: <SubtitleTrackOption>[
        SubtitleTrackOption(
          mediaGuid: 'media-1',
          guid: 'local:file:///tmp/demo.ass',
          title: 'demo.zh.ass',
          codecName: 'ass',
          format: 'ass',
          language: 'zho',
          index: -1,
          isDefault: 1,
          forced: 0,
          isExternal: 1,
          extraFile: 1,
          isBitmap: 0,
        ),
      ],
      status: DownloadTaskStatus.downloaded,
      errorMessage: '',
      createdAtMs: 1,
      updatedAtMs: 2,
    );

    final decoded = DownloadTaskRecord.fromJson(record.toJson());

    expect(decoded.audioTracks, hasLength(1));
    expect(decoded.audioTracks.first.language, 'jpn');
    expect(decoded.audioTracks.first.title, 'Japanese 2.0');
    expect(decoded.subtitleTracks, hasLength(1));
    expect(decoded.subtitleTracks.first.guid, 'local:file:///tmp/demo.ass');
    expect(decoded.subtitleTracks.first.title, 'demo.zh.ass');
    expect(decoded.subtitleTracks.first.language, 'zho');
  });

  test('downloaded lookup respects the selected media version', () {
    const downloadedRecord = DownloadTaskRecord(
      id: 'record-downloaded',
      remoteTaskId: 'remote-downloaded',
      itemGuid: 'item-1',
      mediaGuid: 'media-downloaded',
      groupId: 'group-1',
      groupTitle: 'Group',
      title: 'Episode',
      durationText: '24m',
      posterUrls: <String>[],
      groupPosterUrls: <String>[],
      resolution: '1080P SDR',
      fileName: 'episode-a.mkv',
      filePath: '/tmp/episode-a.mkv',
      totalBytes: 1024,
      downloadedBytes: 1024,
      status: DownloadTaskStatus.downloaded,
      errorMessage: '',
      createdAtMs: 1,
      updatedAtMs: 2,
    );

    final wrongVersion = selectDownloadedRecordForItem(
      const <DownloadTaskRecord>[downloadedRecord],
      'item-1',
      mediaGuid: 'media-online',
      resolution: '1080P SDR',
      isAvailable: (_) => true,
    );
    final selectedVersion = selectDownloadedRecordForItem(
      const <DownloadTaskRecord>[downloadedRecord],
      'item-1',
      mediaGuid: 'media-downloaded',
      resolution: '1080P SDR',
      isAvailable: (_) => true,
    );

    expect(wrongVersion, isNull);
    expect(selectedVersion, downloadedRecord);
  });

  test('download stream selection prefers selected media version', () {
    const firstVersion = StreamListOption(
      mediaGuid: 'media-first',
      videoGuid: 'video-first',
      resolutionType: '1080P SDR',
      colorRangeType: 'SDR',
      audioType: '',
      audioLanguage: '',
      duration: 0,
    );
    const selectedVersion = StreamListOption(
      mediaGuid: 'media-selected',
      videoGuid: 'video-selected',
      resolutionType: '1080P SDR',
      colorRangeType: 'SDR',
      audioType: '',
      audioLanguage: '',
      duration: 0,
    );

    final result = selectDownloadStreamOption(
      const <StreamListOption>[firstVersion, selectedVersion],
      resolution: '1080P SDR',
      mediaGuid: 'media-selected',
    );

    expect(result, selectedVersion);
  });

  test('immediate download record persistence can be awaited', () async {
    final service = DownloadTaskService.instance;
    final tempDir = await Directory.systemTemp.createTemp(
      'fly-player-download-records-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      service.debugSetRecordsFilePathForTesting(null);
    });
    final recordsFile = File('${tempDir.path}/records.json');
    service.debugSetRecordsFilePathForTesting(recordsFile.path);

    const first = DownloadTaskRecord(
      id: 'record-persist',
      remoteTaskId: 'remote-1',
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      groupId: 'group-1',
      groupTitle: 'Group',
      title: 'Episode',
      durationText: '24m',
      posterUrls: <String>[],
      groupPosterUrls: <String>[],
      resolution: '1080P',
      fileName: 'episode.mkv',
      filePath: '/tmp/episode.mkv',
      totalBytes: 100,
      downloadedBytes: 10,
      status: DownloadTaskStatus.downloading,
      errorMessage: '',
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    final second = first.copyWith(
      downloadedBytes: 100,
      status: DownloadTaskStatus.downloaded,
      updatedAtMs: 2,
    );

    service.debugReplaceRecordsForTesting(const <DownloadTaskRecord>[]);
    final firstPersist = service.debugUpsertRecordForTesting(
      first,
      persistImmediately: true,
    );
    final secondPersist = service.debugUpsertRecordForTesting(
      second,
      persistImmediately: true,
    );

    await firstPersist;
    await secondPersist;

    final raw = await recordsFile.readAsString();
    final decoded = jsonDecode(raw) as List<dynamic>;
    final persisted = DownloadTaskRecord.fromJson(
      Map<String, dynamic>.from(decoded.single as Map),
    );
    expect(persisted.downloadedBytes, 100);
    expect(persisted.status, DownloadTaskStatus.downloaded);
  });

  test('download task progress polling skips reentrant requests', () async {
    final service = DownloadTaskService.instance;
    const record = DownloadTaskRecord(
      id: 'record-progress',
      remoteTaskId: 'remote-progress',
      itemGuid: 'item-1',
      mediaGuid: 'media-1',
      groupId: 'group-1',
      groupTitle: 'Group',
      title: 'Episode',
      durationText: '24m',
      posterUrls: <String>[],
      groupPosterUrls: <String>[],
      resolution: '720P',
      fileName: 'episode.mkv',
      filePath: '/tmp/episode.mkv',
      totalBytes: 100,
      downloadedBytes: 10,
      status: DownloadTaskStatus.downloading,
      errorMessage: '',
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    service.debugReplaceRecordsForTesting(const <DownloadTaskRecord>[record]);

    var requestCount = 0;
    final firstRequest = Completer<DownloadTaskProgressInfo?>();
    final firstPoll = service.debugPollDownloadTaskProgressForTesting(
      recordId: record.id,
      fetchProgress: (_) {
        requestCount += 1;
        return firstRequest.future;
      },
    );
    final secondPoll = service.debugPollDownloadTaskProgressForTesting(
      recordId: record.id,
      fetchProgress: (_) {
        requestCount += 1;
        return Future<DownloadTaskProgressInfo?>.value(
          const DownloadTaskProgressInfo(status: 0, percents: 30),
        );
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(requestCount, 1);

    firstRequest.complete(
      const DownloadTaskProgressInfo(status: 0, percents: 20),
    );
    await firstPoll;
    await secondPoll;

    expect(requestCount, 1);
    expect(service.debugTaskProgressForTesting(record.id)?.percents, 20);
  });
}
