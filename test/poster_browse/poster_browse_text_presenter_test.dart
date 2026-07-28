import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/media_image_ref.dart';
import 'package:fly_player/media_backend/media_item_card.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_display_item.dart';
import 'package:fly_player/screens/poster_browse/poster_browse_text_presenter.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh'));
  final presenter = PosterBrowseTextPresenter(l10n: l10n);

  group('secondaryLabel', () {
    test('单集同时显示季集编号与集标题', () {
      final item = _item(
        type: 'episode',
        episodeTitle: '觉醒',
        seasonNumber: 2,
        episodeNumber: 5,
      );

      expect(
        presenter.secondaryLabel(item),
        '${l10n.detailSeasonEpisodeNumber(2, 5)} · 觉醒',
      );
    });

    test('单集缺少季或集编号时只显示可用编号并保留非空集标题', () {
      expect(
        presenter.secondaryLabel(
          _item(type: 'episode', seasonNumber: 3, episodeTitle: '尾声'),
        ),
        '${l10n.detailSeasonNumber(3)} · 尾声',
      );
      expect(
        presenter.secondaryLabel(_item(type: 'episode', episodeNumber: 7)),
        l10n.detailEpisodeNumber(7),
      );
    });

    test('季条目显示季编号与总集数', () {
      final item = _item(type: 'season', seasonNumber: 4, numberOfEpisodes: 12);

      expect(
        presenter.secondaryLabel(item),
        '${l10n.detailSeasonNumber(4)} · ${l10n.detailEpisodeTotal(12)}',
      );
    });

    test('剧集条目显示季数与总集数', () {
      expect(
        presenter.secondaryLabel(
          _item(type: 'series', numberOfSeasons: 3, numberOfEpisodes: 30),
        ),
        '${l10n.detailTvSeasonCount(3)} · ${l10n.detailEpisodeTotal(30)}',
      );
      expect(
        presenter.secondaryLabel(_item(type: 'tv', numberOfEpisodes: 9)),
        l10n.detailEpisodeTotal(9),
      );
    });

    test('电影和其他类型不显示副标签', () {
      expect(presenter.secondaryLabel(_item(type: 'movie')), isEmpty);
      expect(presenter.secondaryLabel(_item(type: 'person')), isEmpty);
    });
  });

  group('metaTexts', () {
    test('按固定顺序显示元信息并过滤空白与限制题材清晰度数量', () {
      final item = _item(
        ratingText: '9.10',
        releaseYear: '2024',
        genres: const <String>[' 科幻 ', '', '剧情', '冒险', '动画'],
        durationSeconds: 59,
        resolutions: const <String>[' 4K ', '', '1080p', '720p'],
      );

      expect(presenter.metaTexts(item), <String>[
        '★ 9.10',
        '2024',
        '科幻 / 剧情 / 冒险',
        l10n.detailDurationMinutes(1),
        '4K',
        '1080p',
      ]);
    });

    test('隐藏空字段并移除完全重复项但保持首次出现顺序', () {
      final item = _item(
        ratingText: '8',
        releaseYear: '剧情',
        genres: const <String>['剧情'],
        resolutions: const <String>[' 剧情 ', '4K', '4K'],
      );

      expect(presenter.metaTexts(item), <String>['★ 8', '剧情', '4K']);
      expect(presenter.metaTexts(_item()), isEmpty);
    });

    test('返回列表不可修改', () {
      final texts = presenter.metaTexts(_item(ratingText: '7.5'));

      expect(() => texts.add('extra'), throwsUnsupportedError);
    });
  });
}

PosterBrowseDisplayItem _item({
  String title = '标题',
  String episodeTitle = '',
  String type = 'movie',
  String ratingText = '',
  String releaseYear = '',
  int seasonNumber = 0,
  int episodeNumber = 0,
  int numberOfSeasons = 0,
  int numberOfEpisodes = 0,
  int durationSeconds = 0,
  List<String> genres = const <String>[],
  List<String> resolutions = const <String>[],
}) {
  return PosterBrowseDisplayItem(
    card: MediaItemCard(
      id: 'item-1',
      title: title,
      type: type,
      primaryImage: MediaImageRef.empty,
    ),
    title: title,
    episodeTitle: episodeTitle,
    type: type,
    seriesId: '',
    ratingText: ratingText,
    releaseYear: releaseYear,
    overview: '',
    detailTargetId: 'item-1',
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    numberOfSeasons: numberOfSeasons,
    numberOfEpisodes: numberOfEpisodes,
    durationSeconds: durationSeconds,
    genres: genres,
    resolutions: resolutions,
    backgroundImages: const <MediaImageRef>[],
    logoImages: const <MediaImageRef>[],
    posterImages: const <MediaImageRef>[],
  );
}
