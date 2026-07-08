import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/models/media_info.dart';
import 'package:fly_player/models/playback_stream.dart';

void main() {
  test('MediaInfo skips malformed nested stream payloads', () {
    final info = MediaInfo.fromJson(<String, dynamic>{
      'file_stream': '',
      'video_stream': <Object?>['bad'],
      'audio_streams': <Object?>[
        'bad',
        <String, dynamic>{'index': 2, 'codec': 'aac', 'language': 'jpn'},
      ],
      'subtitle_streams': <Object?>[
        null,
        <String, dynamic>{'index': 4, 'codec': 'ass', 'language': 'chi'},
      ],
      'qualities': <Object?>[
        123,
        <String, dynamic>{'id': 'origin', 'name': '原画'},
      ],
    });

    expect(info.fileStream, isNull);
    expect(info.videoStream, isNull);
    expect(info.audioStreams, hasLength(1));
    expect(info.audioStreams.single.index, 2);
    expect(info.subtitleStreams, hasLength(1));
    expect(info.subtitleStreams.single.index, 4);
    expect(info.qualities, hasLength(1));
    expect(info.qualities.single.id, 'origin');
  });

  test('PlaybackStreamData ignores malformed response header payload', () {
    final data = PlaybackStreamData.fromJson(<String, dynamic>{
      'header': '',
      'direct_link_qualities': <Map<String, dynamic>>[
        <String, dynamic>{'url': 'https://example.test/video.mp4'},
      ],
    }, requestUserAgent: 'FlyPlayer/1.0');

    expect(data.responseHeaders.cookieHeader, isEmpty);
    expect(data.responseHeaders.primaryUserAgent, isEmpty);
    expect(data.directLinkQualities, hasLength(1));

    final target = data.buildDirectLinkTarget(0);
    expect(target, isNotNull);
    expect(target!.headers, <String, String>{'User-Agent': 'FlyPlayer/1.0'});
  });
}
