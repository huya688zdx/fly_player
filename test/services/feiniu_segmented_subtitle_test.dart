import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/api/feiniu_api.dart';
import 'package:fly_player/models/stream_track_data.dart';
import 'package:fly_player/playback/playback_source.dart';
import 'package:fly_player/providers/nas_provider.dart';
import 'package:fly_player/services/feiniu_segmented_subtitle.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SubtitleApi extends FeiniuApi {
  _SubtitleApi(super.nasProvider);
  final calls = <String>[];
  bool failSegment = false;

  @override
  Future<String> readServerSubtitleResource(String path) async {
    calls.add(path);
    if (path.endsWith('preset.m3u8')) {
      return '#EXTM3U\n#EXT-X-MEDIA:TYPE=SUBTITLES,URI="subtitle.m3u8"';
    }
    if (path.endsWith('subtitle.m3u8')) {
      return '#EXTM3U\n${List.generate(40, (i) => '#EXTINF:4,\n$i.vtt').join('\n')}';
    }
    if (failSegment) throw const SocketException('分段尚未生成');
    return 'WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n\n'
        '02:02.080 --> 02:04.750\n测试字幕\n';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _SubtitleApi api;
  late FeiniuSegmentedSubtitle subtitles;
  final source = MpvMediaSource(
    itemGuid: 'item',
    mediaGuid: 'media',
    videoGuid: 'video',
    url: '',
    headers: const {},
    title: '',
    playLink: '/v/media/session/preset.m3u8',
    playbackMode: PlayerPlaybackMode.serverSession,
    subtitleTrackGuid: 'sub',
    subtitleTracks: [
      SubtitleTrackOption.fromJson({
        'guid': 'sub',
        'format': 'srt',
        'is_external': 0,
        'is_bitmap': 0,
      }),
    ],
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final nas = NasProvider();
    await Future<void>.delayed(Duration.zero);
    api = _SubtitleApi(nas);
    subtitles = FeiniuSegmentedSubtitle(api);
    addTearDown(() async {
      await subtitles.dispose();
      nas.dispose();
    });
  });

  test('从当前时间预取字幕并保持整片时间轴，重载后重新挂载', () async {
    final path = await subtitles.resolve(source, const Duration(seconds: 120));
    final text = await File(path!).readAsString();
    expect(text, 'WEBVTT\n\n02:02.080 --> 02:04.750\n测试字幕\n');
    expect(api.calls.where((p) => p.endsWith('.vtt')).length, 5);
    expect(api.calls, isNot(contains('/v/media/session/0.vtt')));
    expect(
      await subtitles.resolve(source, const Duration(seconds: 120)),
      isNull,
    );
    expect(
      await subtitles.resolve(
        source.copyWith(loadNonce: 2),
        const Duration(seconds: 120),
      ),
      isNotNull,
    );
    final count = api.calls.length;
    await subtitles.resolve(
      source.copyWith(playbackMode: PlayerPlaybackMode.originalQuality),
      Duration.zero,
    );
    expect(api.calls.length, count);
  });

  test('未生成的分段可重试，不把下载失败记成永久空字幕', () async {
    api.failSegment = true;
    expect(
      await subtitles.resolve(source, const Duration(seconds: 120)),
      isNull,
    );
    api.failSegment = false;
    final path = await subtitles.resolve(source, const Duration(seconds: 120));
    expect(await File(path!).readAsString(), contains('测试字幕'));
  });
}
