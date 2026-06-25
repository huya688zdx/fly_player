import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/media_backend/emby/emby_playback_mappers.dart';
import 'package:fly_player/media_backend/playback/media_playback.dart';

void main() {
  Map<String, Object?> source() => <String, Object?>{
    'Id': 'src-1',
    'Container': 'mkv',
    'DefaultAudioStreamIndex': 1,
    'DefaultSubtitleStreamIndex': 3,
    'MediaStreams': <Object?>[
      <String, Object?>{
        'Type': 'Video',
        'Index': 0,
        'Codec': 'hevc',
        'Width': 1920,
        'Height': 1080,
        'BitDepth': 10,
        'ColorSpace': 'bt2020nc',
        'ColorTransfer': 'smpte2084',
        'ColorPrimaries': 'bt2020',
        'Profile': 'Main 10',
      },
      <String, Object?>{
        'Type': 'Audio',
        'Index': 1,
        'Codec': 'eac3',
        'Language': 'eng',
        'DisplayTitle': 'English EAC3 5.1',
      },
      <String, Object?>{
        'Type': 'Audio',
        'Index': 2,
        'Codec': 'aac',
        'Language': 'jpn',
      },
      <String, Object?>{
        'Type': 'Subtitle',
        'Index': 3,
        'Codec': 'subrip',
        'Language': 'chi',
        'DisplayTitle': '简体中文',
        'IsExternal': false,
      },
      <String, Object?>{
        'Type': 'Subtitle',
        'Index': 4,
        'Codec': 'ass',
        'Language': 'chi',
        'IsExternal': true,
      },
    ],
  };

  test('mapEmbyPlaybackSource 取视频属性 + 直链投递', () {
    final src = mapEmbyPlaybackSource(
      source(),
      url: 'https://emby.test/Videos/x/stream?Static=true',
      headers: const <String, String>{'Cookie': 'entry-token=abc'},
    );
    expect(src.id, 'src-1');
    expect(src.delivery, MediaPlaybackDeliveryKind.directLink);
    expect(src.videoTrackId, '0');
    expect(src.width, 1920);
    expect(src.height, 1080);
    expect(src.videoCodec, 'hevc');
    expect(src.bitDepth, 10);
    expect(src.colorTransfer, 'smpte2084');
    expect(src.reliableSeek, isTrue);
    expect(src.forceNativeProxy, isFalse);
    expect(src.headers['Cookie'], 'entry-token=abc');
  });

  test('mapEmbyPlaybackTracks 抽音轨/字幕 + 默认标记 + 外挂位置', () {
    final tracks = mapEmbyPlaybackTracks(source());
    expect(tracks.audio.map((t) => t.id).toList(), <String>['1', '2']);
    expect(tracks.subtitle.map((t) => t.id).toList(), <String>['3', '4']);

    final defaultAudio = tracks.audio.firstWhere((t) => t.isDefault);
    expect(defaultAudio.id, '1');
    expect(defaultAudio.label, 'English EAC3 5.1');
    expect(tracks.audio.where((t) => t.isDefault).length, 1);

    final embedded = tracks.subtitle.firstWhere((t) => t.id == '3');
    expect(embedded.isDefault, isTrue);
    expect(embedded.subtitleLocation, MediaSubtitleLocation.embedded);
    expect(embedded.label, '简体中文');

    final external = tracks.subtitle.firstWhere((t) => t.id == '4');
    expect(external.subtitleLocation, MediaSubtitleLocation.external);
    expect(external.isDefault, isFalse);
  });

  test('默认轨 id 字符串：缺失/负值返回空', () {
    expect(embyDefaultAudioId(source()), '1');
    expect(embyDefaultSubtitleId(source()), '3');
    expect(
      embyDefaultSubtitleId(<String, Object?>{
        'DefaultSubtitleStreamIndex': -1,
      }),
      '',
    );
    expect(embyDefaultAudioId(<String, Object?>{}), '');
  });

  test('无音轨/字幕流时返回空列表', () {
    final tracks = mapEmbyPlaybackTracks(<String, Object?>{
      'MediaStreams': <Object?>[
        <String, Object?>{'Type': 'Video', 'Index': 0},
      ],
    });
    expect(tracks.audio, isEmpty);
    expect(tracks.subtitle, isEmpty);
  });
}
