import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/media_backend/emby/emby_media_mappers.dart';

void main() {
  const serverUrl = 'https://emby.example.test';
  const token = 'tok';

  group('mapEmbyView', () {
    test('媒体库 → MediaCatalog（type 取 CollectionType，图片带 api_key）', () {
      final catalog = mapEmbyView(
        <String, Object?>{
          'Id': 'lib-1',
          'Name': '电影',
          'CollectionType': 'movies',
          'ImageTags': <String, Object?>{'Primary': 'abc'},
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(catalog.id, 'lib-1');
      expect(catalog.title, '电影');
      expect(catalog.type, 'movies');
      expect(
        catalog.primaryImage.url,
        'https://emby.example.test/Items/lib-1/Images/Primary?tag=abc&api_key=tok',
      );
      expect(catalog.posters, hasLength(1));
    });

    test('无 Primary 图 → 图片空、posters 空', () {
      final catalog = mapEmbyView(
        <String, Object?>{
          'Id': 'lib-2',
          'Name': '剧集',
          'Type': 'CollectionFolder',
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(catalog.type, 'CollectionFolder');
      expect(catalog.primaryImage.isEmpty, isTrue);
      expect(catalog.posters, isEmpty);
    });
  });

  group('mapEmbyItemCard', () {
    test('影片 → MediaItemCard（ticks→秒、Played、评分、图片）', () {
      final card = mapEmbyItemCard(
        <String, Object?>{
          'Id': 'item-1',
          'Name': '影片甲',
          'Type': 'Movie',
          'RunTimeTicks': 72000000000, // 7200 秒
          'CommunityRating': 8.6,
          'PremiereDate': '2020-01-01T00:00:00.0000000Z',
          'ImageTags': <String, Object?>{'Primary': 'p1'},
          'BackdropImageTags': <Object?>['b1'],
          'UserData': <String, Object?>{'Played': true},
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(card.id, 'item-1');
      expect(card.title, '影片甲');
      expect(card.type, 'Movie');
      expect(card.durationSeconds, 7200);
      expect(card.watched, isTrue);
      expect(card.rating, '8.6');
      expect(card.releaseDate, '2020-01-01T00:00:00.0000000Z');
      expect(
        card.primaryImage.url,
        'https://emby.example.test/Items/item-1/Images/Primary?tag=p1&api_key=tok',
      );
      expect(
        card.backdropImage.url,
        'https://emby.example.test/Items/item-1/Images/Backdrop?tag=b1&api_key=tok',
      );
    });

    test('剧集单集：SeriesName→副标题，季/集编号', () {
      final card = mapEmbyItemCard(
        <String, Object?>{
          'Id': 'ep-1',
          'Name': '第三集',
          'Type': 'Episode',
          'SeriesName': '剧集名',
          'ParentIndexNumber': 1,
          'IndexNumber': 3,
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(card.secondaryTitle, '剧集名');
      expect(card.displayTitle, '剧集名');
      expect(card.seasonNumber, 1);
      expect(card.episodeNumber, 3);
      expect(card.watched, isFalse);
      expect(card.durationSeconds, 0);
      expect(card.primaryImage.isEmpty, isTrue);
    });
  });

  group('mapEmbyItemDetail', () {
    test('影片详情：标题/简介/题材/时长/评分/外部 ID/图片/演职员', () {
      final detail = mapEmbyItemDetail(
        <String, Object?>{
          'Id': 'm-1',
          'Name': '银翼杀手 2049',
          'Type': 'Movie',
          'Overview': '简介文本',
          'RunTimeTicks': 9840000000000, // 984000 秒 = 16400 分
          'CommunityRating': 8.0,
          'PremiereDate': '2017-10-06T00:00:00.0000000Z',
          'Genres': <Object?>['科幻', '剧情'],
          'ProductionLocations': <Object?>['美国'],
          'ImageTags': <String, Object?>{'Primary': 'p1', 'Logo': 'lg1'},
          'BackdropImageTags': <Object?>['b1'],
          'ProviderIds': <String, Object?>{
            'Tmdb': '335984',
            'Imdb': 'tt1856101',
          },
          'UserData': <String, Object?>{
            'Played': true,
            'IsFavorite': true,
            'PlaybackPositionTicks': 6000000000, // 600 秒
          },
          'People': <Object?>[
            <String, Object?>{
              'Id': 'pp-1',
              'Name': 'Ryan Gosling',
              'Role': 'K',
              'Type': 'Actor',
              'PrimaryImageTag': 'av1',
            },
            <String, Object?>{
              'Id': 'pp-2',
              'Name': 'Denis Villeneuve',
              'Type': 'Director',
            },
            <String, Object?>{'Id': 'pp-3', 'Name': '', 'Type': 'Actor'},
          ],
        },
        serverUrl: serverUrl,
        token: token,
      );

      expect(detail.id, 'm-1');
      expect(detail.type, 'Movie');
      expect(detail.title, '银翼杀手 2049');
      expect(detail.overview, '简介文本');
      expect(detail.genreLabels, <String>['科幻', '剧情']);
      expect(detail.regionLabels, <String>['美国']);
      expect(detail.durationSeconds, 984000);
      expect(detail.runtimeMinutes, 16400);
      expect(detail.rating, '8.0');
      expect(detail.releaseDate, '2017-10-06T00:00:00.0000000Z');
      expect(detail.externalIds.tmdbId, '335984');
      expect(detail.externalIds.imdbId, 'tt1856101');
      expect(detail.watched, isTrue);
      expect(detail.favorite, isTrue);
      expect(detail.resumePositionSeconds, 600);
      expect(
        detail.primaryImage.url,
        'https://emby.example.test/Items/m-1/Images/Primary?tag=p1&api_key=tok',
      );
      expect(
        detail.logoImage.url,
        'https://emby.example.test/Items/m-1/Images/Logo?tag=lg1&api_key=tok',
      );
      expect(
        detail.backdropImage.url,
        'https://emby.example.test/Items/m-1/Images/Backdrop?tag=b1&api_key=tok',
      );
      // 无名演职员被剔除；其余保留顺序、department=Type。
      expect(detail.people, hasLength(2));
      expect(detail.people[0].name, 'Ryan Gosling');
      expect(detail.people[0].role, 'K');
      expect(detail.people[0].department, 'Actor');
      expect(
        detail.people[0].avatar.url,
        'https://emby.example.test/Items/pp-1/Images/Primary?tag=av1&api_key=tok',
      );
      expect(detail.people[1].name, 'Denis Villeneuve');
      expect(detail.people[1].department, 'Director');
      expect(detail.people[1].avatar.isEmpty, isTrue);
    });

    test('缺图缺人缺外部 ID：空态降级不报错，年份回退 ProductionYear', () {
      final detail = mapEmbyItemDetail(
        <String, Object?>{
          'Id': 'm-2',
          'Name': '某电影',
          'Type': 'Movie',
          'ProductionYear': 1999,
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(detail.releaseDate, '1999');
      expect(detail.primaryImage.isEmpty, isTrue);
      expect(detail.logoImage.isEmpty, isTrue);
      expect(detail.genreLabels, isEmpty);
      expect(detail.people, isEmpty);
      expect(detail.externalIds.tmdbId, isEmpty);
      expect(detail.externalIds.imdbId, isEmpty);
      expect(detail.watched, isFalse);
    });
  });

  group('mapEmbySourceInfo', () {
    test('MediaSources + MediaStreams → 文件信息 + 视频/音频/字幕摘要', () {
      final info = mapEmbySourceInfo(<String, Object?>{
        'DateCreated': '2026-02-06T11:48:00.0000000Z',
        'MediaSources': <Object?>[
          <String, Object?>{
            'Path': '/vol4/1000/动漫电影3/Love.mkv',
            'Container': 'mkv',
            'Size': 6442450944, // 6 GiB
            'MediaStreams': <Object?>[
              <String, Object?>{
                'Type': 'Video',
                'DisplayTitle': '1080p H264',
                'Codec': 'h264',
                'Height': 1080,
                'BitRate': 9000000,
                'BitDepth': 10,
              },
              <String, Object?>{
                'Type': 'Audio',
                'DisplayTitle': 'Japanese FLAC 5.1 (默认)',
                'Codec': 'flac',
                'ChannelLayout': '5.1',
                'SampleRate': 48000,
              },
              <String, Object?>{
                'Type': 'Subtitle',
                'DisplayTitle': 'Chinese Simplified ASS',
                'Codec': 'ass',
                'IsExternal': true,
              },
            ],
          },
        ],
      });

      expect(info.path, '/vol4/1000/动漫电影3/Love.mkv');
      expect(info.container, 'mkv');
      expect(info.sizeBytes, 6442450944);
      expect(info.addedDate, '2026-02-06T11:48:00.0000000Z');

      expect(info.videoStreams, hasLength(1));
      expect(info.videoStreams.first.label, '1080p H264');
      expect(info.videoStreams.first.summary, '9.00 mbps · 10 bit');

      expect(info.audioStreams, hasLength(1));
      expect(info.audioStreams.first.label, 'Japanese FLAC 5.1 (默认)');
      expect(info.audioStreams.first.summary, '48000 Hz');

      expect(info.subtitleStreams, hasLength(1));
      expect(info.subtitleStreams.first.label, 'Chinese Simplified ASS');
      expect(info.subtitleStreams.first.summary, '外挂');
    });

    test('无 MediaSources → isEmpty', () {
      final info = mapEmbySourceInfo(const <String, Object?>{
        'Id': 'm-1',
        'Name': '某电影',
      });
      expect(info.isEmpty, isTrue);
    });

    test('视频无 DisplayTitle → 用分辨率+编码拼 label', () {
      final info = mapEmbySourceInfo(<String, Object?>{
        'MediaSources': <Object?>[
          <String, Object?>{
            'MediaStreams': <Object?>[
              <String, Object?>{
                'Type': 'Video',
                'Codec': 'hevc',
                'Height': 2160,
              },
            ],
          },
        ],
      });
      expect(info.videoStreams.first.label, '2160p HEVC');
    });
  });

  group('mapEmbySeason', () {
    test('季 → MediaSeasonSummary（ChildCount 充当总数与本地数，图片带 api_key）', () {
      final season = mapEmbySeason(
        <String, Object?>{
          'Id': 'season-1',
          'Name': '第 1 季',
          'IndexNumber': 1,
          'ChildCount': 12,
          'ImageTags': <String, Object?>{'Primary': 'sp'},
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(season.id, 'season-1');
      expect(season.title, '第 1 季');
      expect(season.seasonNumber, 1);
      expect(season.numberOfEpisodes, 12);
      expect(season.localNumberOfEpisodes, 12);
      expect(
        season.primaryImage.url,
        'https://emby.example.test/Items/season-1/Images/Primary?tag=sp&api_key=tok',
      );
    });

    test('无 ChildCount 时回退 RecursiveItemCount', () {
      final season = mapEmbySeason(
        <String, Object?>{
          'Id': 'season-2',
          'Name': '第 2 季',
          'IndexNumber': 2,
          'RecursiveItemCount': 8,
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(season.numberOfEpisodes, 8);
      expect(season.primaryImage.isEmpty, isTrue);
    });
  });

  group('mapEmbyEpisode', () {
    test('集 → MediaEpisodeSummary（时长 RunTimeTicks→秒，续播取 UserData）', () {
      final episode = mapEmbyEpisode(
        <String, Object?>{
          'Id': 'ep-1',
          'Name': '第一集',
          'ParentIndexNumber': 1,
          'IndexNumber': 1,
          'Overview': '开场',
          'PremiereDate': '2023-01-05',
          'RunTimeTicks': 14400000000,
          'UserData': <String, Object?>{
            'Played': true,
            'PlaybackPositionTicks': 3000000000,
          },
        },
        serverUrl: serverUrl,
        token: token,
      );
      expect(episode.id, 'ep-1');
      expect(episode.title, '第一集');
      expect(episode.seasonNumber, 1);
      expect(episode.episodeNumber, 1);
      expect(episode.overview, '开场');
      expect(episode.airDate, '2023-01-05');
      expect(episode.durationSeconds, 1440);
      expect(episode.watched, isTrue);
      expect(episode.resumePositionSeconds, 300);
    });

    test('无 UserData → 未看、续播 0', () {
      final episode = mapEmbyEpisode(
        <String, Object?>{'Id': 'ep-2', 'Name': '第二集', 'IndexNumber': 2},
        serverUrl: serverUrl,
        token: token,
      );
      expect(episode.watched, isFalse);
      expect(episode.resumePositionSeconds, 0);
    });
  });

  group('mapEmbySourceVersions', () {
    test('多源 → 多版本：label/badges/轨道/默认轨', () {
      final versions = mapEmbySourceVersions(<String, Object?>{
        'DateCreated': '2024-01-01T00:00:00Z',
        'MediaSources': <Object?>[
          <String, Object?>{
            'Id': 'src-4k',
            'Path': '/movies/a.4k.mkv',
            'Container': 'mkv',
            'Size': 200,
            'DefaultAudioStreamIndex': 1,
            'DefaultSubtitleStreamIndex': 3,
            'MediaStreams': <Object?>[
              <String, Object?>{
                'Type': 'Video',
                'Index': 0,
                'Height': 2160,
                'VideoRange': 'HDR',
              },
              <String, Object?>{
                'Type': 'Audio',
                'Index': 1,
                'DisplayTitle': '国语 FLAC 5.1',
                'Codec': 'flac',
                'ChannelLayout': '5.1',
              },
              <String, Object?>{
                'Type': 'Subtitle',
                'Index': 3,
                'DisplayTitle': '简体中文',
                'IsExternal': true,
              },
            ],
          },
          <String, Object?>{
            'Id': 'src-1080',
            'Container': 'mp4',
            'MediaStreams': <Object?>[
              <String, Object?>{'Type': 'Video', 'Index': 0, 'Height': 1080},
            ],
          },
        ],
      });

      expect(versions, hasLength(2));
      final v0 = versions[0];
      expect(v0.id, 'src-4k');
      expect(v0.label, '2160p');
      expect(v0.badges, containsAll(<String>['2160p', 'HDR']));
      expect(v0.info.path, '/movies/a.4k.mkv');
      expect(v0.info.addedDate, '2024-01-01T00:00:00Z');
      expect(v0.audioTracks, hasLength(1));
      expect(v0.audioTracks.first.id, '1');
      expect(v0.audioTracks.first.label, '国语 FLAC 5.1');
      expect(v0.subtitleTracks, hasLength(1));
      expect(v0.subtitleTracks.first.id, '3');
      expect(v0.subtitleTracks.first.isExternal, isTrue);
      expect(v0.defaultAudioId, '1');
      expect(v0.defaultSubtitleId, '3');

      // SDR 不进 badges；无默认字幕索引 → 空。
      expect(versions[1].label, '1080p');
      expect(versions[1].badges, <String>['1080p']);
      expect(versions[1].defaultSubtitleId, '');
    });

    test('无 MediaSources → 空列表', () {
      expect(mapEmbySourceVersions(<String, Object?>{'Id': 'x'}), isEmpty);
    });
  });
}
