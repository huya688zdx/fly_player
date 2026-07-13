import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/feiniu/feiniu_playback_context.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';
import 'package:fly_player/models/play_info.dart';
import 'package:fly_player/models/playback_stream.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/playback/feiniu_playback_source_bridge.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlayInfoData buildPlayInfo() {
  return PlayInfoData.fromJson(<String, dynamic>{
    'grand_guid': 'series-1',
    'type': 'Episode',
    'ts': 600,
    'media_guid': 'media-1',
    'video_guid': 'video-1',
    'audio_guid': 'audio-1',
    'subtitle_guid': 'sub-1',
    'parent_guid': 'season-1',
    'item': <String, dynamic>{
      'guid': 'item-1',
      'trim_id': 'tmdb-1',
      'type': 'Episode',
      'title': '第 1 集',
      'tv_title': '剧集名',
      'ancestor_name': '剧集库',
      'duration': 3000,
      'season_number': 1,
      'episode_number': 1,
      'posters': '/poster.jpg',
    },
  });
}

const _videoStream = VideoStreamInfo(
  mediaGuid: 'media-1',
  guid: 'video-1',
  resolutionType: '1080p',
  colorRangeType: 'SDR',
  codecName: 'hevc',
  profile: 'Main 10',
  level: '',
  displayAspectRatio: '',
  pixFmt: '',
  rFrameRate: '',
  colorRange: '',
  colorSpace: 'bt709',
  colorTransfer: 'bt709',
  colorPrimaries: 'bt709',
  bps: 8000000,
  bitDepth: 10,
  refs: 0,
  progressive: 0,
  width: 1920,
  height: 1080,
);

const _audio = AudioTrackOption(
  mediaGuid: 'media-1',
  guid: 'audio-1',
  title: '',
  codecName: 'aac',
  profile: '',
  language: 'jpn',
  audioType: '',
  channelLayout: '',
  channels: 2,
  sampleRate: 48000,
  bps: 256000,
  index: 1,
  isDefault: 1,
);

SubtitleTrackOption buildSubtitle({int isExternal = 0, int extraFile = 0}) {
  return SubtitleTrackOption(
    mediaGuid: 'media-1',
    guid: 'sub-1',
    title: '',
    codecName: 'ass',
    format: 'ass',
    language: 'chi',
    index: 0,
    isDefault: 1,
    forced: 0,
    isExternal: isExternal,
    extraFile: extraFile,
    isBitmap: 0,
  );
}

const _originalQuality = PlaybackQualityOption(
  mediaGuid: 'media-1',
  videoGuid: 'video-1',
  resolution: '1080p',
  bitrate: 8000000,
  isDefault: 1,
  source: PlaybackQualitySource.originalProxy,
  directLinkQualityIndex: null,
);

PlaybackStreamData buildStream(List<SubtitleTrackOption> subtitles) {
  return PlaybackStreamData(
    fileStream: null,
    videoStream: _videoStream,
    audioStreams: const <AudioTrackOption>[_audio],
    subtitleStreams: subtitles,
    qualities: const <PlaybackQualityOption>[_originalQuality],
    directLinkQualities: const <DirectLinkQualitySource>[],
    cloudStorageInfo: null,
    responseHeaders: const PlaybackResponseHeaders(),
    requestUserAgent: '',
  );
}

FeiniuPlaybackContext buildContext(
  FeiniuApi api, {
  SubtitleTrackOption? selectedSubtitle,
  List<SubtitleTrackOption> subtitles = const <SubtitleTrackOption>[],
}) {
  final stream = buildStream(subtitles);
  return FeiniuPlaybackContext(
    api: api,
    playInfo: buildPlayInfo(),
    playbackStream: stream,
    selectedQuality: _originalQuality,
    selectedAudio: _audio,
    selectedSubtitle: selectedSubtitle,
    mergedQualities: stream.qualities,
    subtitleTracks: subtitles,
    effectiveSourceId: 'media-1',
    videoTrackId: 'video-1',
    directUrl: 'http://nas.test/play.m3u8',
  );
}

MediaPlaybackBundle buildBundle() {
  return const MediaPlaybackBundle(
    itemId: 'item-1',
    startPosition: Duration(seconds: 600),
    selectedSource: MediaPlaybackSource(
      id: 'media-1',
      videoTrackId: 'video-1',
      delivery: MediaPlaybackDeliveryKind.original,
    ),
    session: MediaPlaybackSession(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));

  setUp(() {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  // NasProvider 构造里异步 _loadSettings 会在加载完成后 notifyListeners；
  // 先 settle 再继续，避免 tearDown dispose 后异步回调命中 "used after disposed"。
  Future<FeiniuApi> makeApi() async {
    final nas = NasProvider();
    addTearDown(nas.dispose);
    await Future<void>.delayed(Duration.zero);
    return FeiniuApi(nas);
  }

  group('FeiniuPlaybackSourceBridge.assemble', () {
    test('原画路径：MpvMediaSource 关键字段与 launcher 口径一致', () async {
      final api = await makeApi();
      final subtitle = buildSubtitle();
      final context = buildContext(
        api,
        selectedSubtitle: subtitle,
        subtitles: <SubtitleTrackOption>[subtitle],
      );

      final source = await const FeiniuPlaybackSourceBridge().assemble(
        request: const MediaPlaybackRequest(itemId: 'item-1'),
        bundle: buildBundle(),
        context: context,
        l10n: l10n,
      );

      expect(source, isA<MpvMediaSource>());
      expect(source.itemGuid, 'item-1');
      expect(source.seriesGuid, 'series-1');
      expect(source.seasonGuid, 'season-1');
      expect(source.mediaGuid, 'media-1');
      expect(source.videoGuid, 'video-1');
      expect(source.url, 'http://nas.test/play.m3u8');
      expect(source.startPosition, const Duration(seconds: 600));
      expect(source.audioTrackIndex, 1);
      expect(source.audioTrackGuid, 'audio-1');
      expect(source.subtitleTrackGuid, 'sub-1');
      // 内嵌字幕第一条 → 序号 1。
      expect(source.subtitleTrackIndex, 1);
      expect(source.preferExternalSubtitle, isFalse);
      expect(source.directLinkQualityIndex, isNull);
      expect(source.playbackMode, PlayerPlaybackMode.originalQuality);
      expect(source.videoWidth, 1920);
      expect(source.videoHeight, 1080);
      expect(source.videoCodecName, 'hevc');
      expect(source.colorSpace, 'bt709');
      expect(source.bitDepth, 10);
      expect(source.durationSeconds, 3000);
      expect(source.qualities, hasLength(1));
      expect(source.audioTracks, hasLength(1));
    });

    test('显式关闭字幕：subtitleTrackGuid 落空串，序号为 null', () async {
      final api = await makeApi();
      final context = buildContext(api, selectedSubtitle: null);

      final source = await const FeiniuPlaybackSourceBridge().assemble(
        request: const MediaPlaybackRequest(
          itemId: 'item-1',
          subtitleTrackExplicitlyDisabled: true,
        ),
        bundle: buildBundle(),
        context: context,
        l10n: l10n,
      );

      expect(source.subtitleTrackGuid, '');
      expect(source.subtitleTrackIndex, isNull);
      expect(source.preferExternalSubtitle, isFalse);
    });

    test('外挂字幕：preferExternalSubtitle 为真，内嵌序号为 null', () async {
      final api = await makeApi();
      final subtitle = buildSubtitle(isExternal: 1);
      final context = buildContext(
        api,
        selectedSubtitle: subtitle,
        subtitles: <SubtitleTrackOption>[subtitle],
      );

      final source = await const FeiniuPlaybackSourceBridge().assemble(
        request: const MediaPlaybackRequest(itemId: 'item-1'),
        bundle: buildBundle(),
        context: context,
        l10n: l10n,
      );

      expect(source.preferExternalSubtitle, isTrue);
      expect(source.subtitleTrackIndex, isNull);
      expect(source.subtitleTrackGuid, 'sub-1');
    });

    test('seriesId 为空：seriesGuid 回退 grandGuid（保 B-2 单条目现状）', () async {
      final api = await makeApi();
      final context = buildContext(api, selectedSubtitle: null);

      final source = await const FeiniuPlaybackSourceBridge().assemble(
        request: const MediaPlaybackRequest(itemId: 'item-1'),
        bundle: buildBundle(),
        context: context,
        l10n: l10n,
      );

      expect(source.seriesGuid, 'series-1');
    });

    test('显式 seriesId：seriesGuid 取覆盖值优先于 grandGuid', () async {
      final api = await makeApi();
      final context = buildContext(api, selectedSubtitle: null);

      final source = await const FeiniuPlaybackSourceBridge().assemble(
        request: const MediaPlaybackRequest(
          itemId: 'item-1',
          seriesId: 'series-override',
        ),
        bundle: buildBundle(),
        context: context,
        l10n: l10n,
      );

      expect(source.seriesGuid, 'series-override');
    });
  });
}
