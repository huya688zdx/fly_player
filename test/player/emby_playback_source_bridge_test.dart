import 'package:flutter_test/flutter_test.dart';

import 'package:fly_player/media_backend/playback/media_playback.dart';
import 'package:fly_player/playback/emby_playback_source_bridge.dart';

void main() {
  MediaPlaybackBundle bundle({
    MediaPlaybackTrack? selectedAudio,
    MediaPlaybackTrack? selectedSubtitle,
    Duration startPosition = const Duration(seconds: 600),
    Map<String, String> headers = const <String, String>{},
    String seriesTitle = '',
  }) {
    const audioTracks = <MediaPlaybackTrack>[
      MediaPlaybackTrack(id: '1', kind: MediaPlaybackTrackKind.audio, index: 1),
      MediaPlaybackTrack(id: '2', kind: MediaPlaybackTrackKind.audio, index: 2),
    ];
    const subtitleTracks = <MediaPlaybackTrack>[
      MediaPlaybackTrack(
        id: '3',
        kind: MediaPlaybackTrackKind.subtitle,
        index: 3,
        subtitleLocation: MediaSubtitleLocation.embedded,
      ),
      MediaPlaybackTrack(
        id: '4',
        kind: MediaPlaybackTrackKind.subtitle,
        index: 4,
        subtitleLocation: MediaSubtitleLocation.external,
      ),
    ];
    return MediaPlaybackBundle(
      itemId: 'item-5',
      title: '测试电影',
      itemType: 'Movie',
      seriesId: 'series-9',
      seriesTitle: seriesTitle,
      seasonId: 'season-3',
      seasonNumber: 2,
      episodeNumber: 7,
      tmdbId: '12345',
      durationSeconds: 7200,
      startPosition: startPosition,
      selectedSource: MediaPlaybackSource(
        id: 'src-1',
        videoTrackId: '0',
        delivery: MediaPlaybackDeliveryKind.directLink,
        url: 'https://emby.test/Videos/item-5/stream.mkv?Static=true',
        headers: headers,
        width: 1920,
        height: 1080,
        videoCodec: 'hevc',
        bitDepth: 10,
        reliableSeek: true,
      ),
      selectedAudioTrack: selectedAudio,
      selectedSubtitleTrack: selectedSubtitle,
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      session: const MediaPlaybackSession(),
    );
  }

  test('装配直链 source：url/headers/视频属性/续播位透传', () async {
    final source = await const EmbyPlaybackSourceBridge().assemble(
      request: const MediaPlaybackRequest(itemId: 'item-5'),
      bundle: bundle(
        headers: const <String, String>{'Cookie': 'entry-token=abc'},
        selectedAudio: const MediaPlaybackTrack(
          id: '1',
          kind: MediaPlaybackTrackKind.audio,
          index: 1,
        ),
      ),
    );
    expect(source.itemGuid, 'item-5');
    expect(source.mediaGuid, 'src-1');
    expect(source.url, contains('/Videos/item-5/stream.mkv'));
    expect(source.headers['Cookie'], 'entry-token=abc');
    expect(source.videoWidth, 1920);
    expect(source.bitDepth, 10);
    expect(source.resolution, '1080p');
    expect(source.startPosition, const Duration(seconds: 600));
    expect(source.title, '测试电影');
    expect(source.tmdbId, '12345');
    expect(source.seriesGuid, 'series-9');
  });

  test('音轨/字幕按同类型 1-based 序号映射 mpv 轨道号', () async {
    final source = await const EmbyPlaybackSourceBridge().assemble(
      request: const MediaPlaybackRequest(itemId: 'item-5'),
      bundle: bundle(
        selectedAudio: const MediaPlaybackTrack(
          id: '2',
          kind: MediaPlaybackTrackKind.audio,
          index: 2,
        ),
        selectedSubtitle: const MediaPlaybackTrack(
          id: '3',
          kind: MediaPlaybackTrackKind.subtitle,
          index: 3,
          subtitleLocation: MediaSubtitleLocation.embedded,
        ),
      ),
    );
    // 第二条音轨 → mpv aid 2；内嵌字幕中第一条 → mpv sid 1。
    expect(source.audioTrackIndex, 2);
    expect(source.subtitleTrackIndex, 1);
    expect(source.preferExternalSubtitle, isFalse);
    expect(source.audioTrackGuid, '2');
  });

  test('外挂字幕：subtitleTrackIndex 留空 + preferExternalSubtitle', () async {
    final source = await const EmbyPlaybackSourceBridge().assemble(
      request: const MediaPlaybackRequest(itemId: 'item-5'),
      bundle: bundle(
        selectedSubtitle: const MediaPlaybackTrack(
          id: '4',
          kind: MediaPlaybackTrackKind.subtitle,
          index: 4,
          subtitleLocation: MediaSubtitleLocation.external,
        ),
      ),
    );
    expect(source.subtitleTrackIndex, isNull);
    expect(source.preferExternalSubtitle, isTrue);
  });

  test('显式关闭字幕：subtitleTrackGuid 空串、不选字幕', () async {
    final source = await const EmbyPlaybackSourceBridge().assemble(
      request: const MediaPlaybackRequest(
        itemId: 'item-5',
        subtitleTrackExplicitlyDisabled: true,
      ),
      bundle: bundle(),
    );
    expect(source.subtitleTrackGuid, '');
    expect(source.subtitleTrackIndex, isNull);
  });

  test('请求显式 seriesId 优先于 bundle', () async {
    final source = await const EmbyPlaybackSourceBridge().assemble(
      request: const MediaPlaybackRequest(
        itemId: 'item-5',
        seriesId: 'explicit-series',
      ),
      bundle: bundle(),
    );
    expect(source.seriesGuid, 'explicit-series');
  });

  test('audioTracks 全量映射飞牛 DTO（喂壳内 picker），顺序=容器顺序', () async {
    final source = await const EmbyPlaybackSourceBridge().assemble(
      request: const MediaPlaybackRequest(itemId: 'item-5'),
      bundle: bundle(
        selectedAudio: const MediaPlaybackTrack(
          id: '2',
          kind: MediaPlaybackTrackKind.audio,
          index: 2,
        ),
      ),
    );
    expect(source.audioTracks.map((t) => t.guid).toList(), <String>['1', '2']);
    expect(source.audioTracks.first.mediaGuid, 'src-1');
    // 选择器用列表 1-based 位置当 mpv aid，故顺序必须 = 容器顺序。
    expect(source.audioTracks[1].guid, '2');
  });

  test('subtitleTracks 内嵌用 Index、外挂用自包含 guid + isExternal=1', () async {
    final source = await const EmbyPlaybackSourceBridge().assemble(
      request: const MediaPlaybackRequest(itemId: 'item-5'),
      bundle: bundle(),
    );
    // bundle 含内嵌(id=3) + 外挂(id=4)：内嵌 guid=Index，外挂 guid=自包含编码。
    final guids = source.subtitleTracks.map((t) => t.guid).toList();
    expect(guids, <String>['3', 'emby:sub:item-5:src-1:4']);
    final embedded = source.subtitleTracks.firstWhere((t) => t.guid == '3');
    expect(embedded.isExternal, 0);
    final external = source.subtitleTracks.firstWhere(
      (t) => t.guid == 'emby:sub:item-5:src-1:4',
    );
    expect(external.isExternal, 1);
    expect(external.extraFile, 1);
  });

  test('选中外挂字幕：subtitleTrackGuid 用自包含 guid + preferExternalSubtitle', () async {
    final source = await const EmbyPlaybackSourceBridge().assemble(
      request: const MediaPlaybackRequest(itemId: 'item-5'),
      bundle: bundle(
        selectedSubtitle: const MediaPlaybackTrack(
          id: '4',
          kind: MediaPlaybackTrackKind.subtitle,
          index: 4,
          subtitleLocation: MediaSubtitleLocation.external,
        ),
      ),
    );
    expect(source.subtitleTrackGuid, 'emby:sub:item-5:src-1:4');
    expect(source.subtitleTrackIndex, isNull);
    expect(source.preferExternalSubtitle, isTrue);
  });

  test('电影（系列名空）seriesTitle 回退标题，供弹幕匹配', () async {
    final source = await const EmbyPlaybackSourceBridge().assemble(
      request: const MediaPlaybackRequest(itemId: 'item-5'),
      bundle: bundle(),
    );
    expect(source.seriesTitle, '测试电影');
  });

  test('剧集（系列名非空）保留系列名', () async {
    final source = await const EmbyPlaybackSourceBridge().assemble(
      request: const MediaPlaybackRequest(itemId: 'item-5'),
      bundle: bundle(seriesTitle: '某剧集'),
    );
    expect(source.seriesTitle, '某剧集');
  });
}
