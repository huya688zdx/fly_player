import '../l10n/generated/app_localizations.dart';
import '../media_backend/detail/media_detail.dart';
import '../models/play_info.dart';
import 'api_url_helper.dart';

class PlayDetailFormatters {
  PlayDetailFormatters._();

  static String originFromBaseUrl(String baseUrl) {
    return ApiUrlHelper.originFromBaseUrl(baseUrl);
  }

  static List<String> imageCandidates(
    String baseUrl,
    String path, {
    int width = 900,
  }) {
    return ApiUrlHelper.imageCandidates(baseUrl, path, width: width);
  }

  static List<String> personImageCandidates(
    String baseUrl,
    String path, {
    int width = 320,
  }) {
    return ApiUrlHelper.personImageCandidates(baseUrl, path, width: width);
  }

  static String year(PlayItem item) {
    final date = item.releaseDate.isNotEmpty ? item.releaseDate : item.airDate;
    return date.length >= 4 ? date.substring(0, 4) : '';
  }

  static String runtimeText(PlayItem item, AppLocalizations l10n) {
    if (item.runtime > 0) return l10n.detailDurationMinutes(item.runtime);
    return formatDuration(item.duration, l10n);
  }

  static String formatDuration(int durationSeconds, AppLocalizations l10n) {
    if (durationSeconds <= 0) return '';
    final hour = durationSeconds ~/ 3600;
    final minute = (durationSeconds % 3600) ~/ 60;
    final second = durationSeconds % 60;

    if (hour > 0) return l10n.detailDurationHoursMinutes(hour, minute);
    if (minute > 0) {
      return second > 0
          ? l10n.detailDurationMinutesSeconds(minute, second)
          : l10n.detailDurationMinutes(minute);
    }
    return l10n.detailDurationSeconds(second);
  }

  static List<String> genreNamesFromIds(
    Iterable<dynamic> genres, {
    Map<int, String> genreMap = const <int, String>{},
    int maxCount = 4,
  }) {
    final out = <String>[];
    for (final raw in genres) {
      if (out.length >= maxCount) break;
      final id = int.tryParse('$raw');
      if (id == null) continue;
      final label = genreMap[id]?.trim();
      if (label != null && label.isNotEmpty) out.add(label);
    }
    return out;
  }

  static List<String> countryNames(
    PlayItem item, {
    Map<String, String> locateMap = const <String, String>{},
  }) {
    return item.productionCountries
        .map((e) => locateMap[e.toUpperCase()] ?? e)
        .toList();
  }

  static List<String> countryNamesFromCodes(
    Iterable<dynamic> countries, {
    Map<String, String> locateMap = const <String, String>{},
  }) {
    return countries
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => locateMap[e.toUpperCase()] ?? e)
        .toList();
  }

  static String remainText(int duration, int ts, AppLocalizations l10n) {
    if (duration <= 0) return '';
    final remainSeconds = (duration - ts).clamp(0, duration);
    final hour = remainSeconds ~/ 3600;
    final minute = remainSeconds ~/ 60;
    final second = remainSeconds % 60;
    if (hour > 0) {
      final minuteInHour = (remainSeconds % 3600) ~/ 60;
      return l10n.detailRemainingDurationHoursMinutesSeconds(
        hour,
        minuteInHour,
        second,
      );
    }
    return l10n.detailRemainingDurationMinutesSeconds(minute, second);
  }

  static double progress(int duration, int ts) {
    if (duration <= 0) return 0;
    return (ts / duration).clamp(0.0, 1.0);
  }

  static String metaLineA(
    PlayItem item, {
    Map<int, String> genreMap = const <int, String>{},
    Map<String, String> locateMap = const <String, String>{},
  }) {
    final values = [
      if (item.voteAverage.isNotEmpty && item.voteAverage != '0') 'PG',
      year(item),
      ...genreNamesFromIds(item.genres, genreMap: genreMap),
      ...countryNames(item, locateMap: locateMap),
    ].where((e) => e.isNotEmpty);
    return values.join(' / ');
  }

  static String metaLineB(PlayItem item, AppLocalizations l10n) {
    final values = [
      runtimeText(item, l10n),
      item.ancestorName,
    ].where((e) => e.isNotEmpty);
    return values.join(' / ');
  }

  /// 中立后端（Emby 等）的 metaLineA：与飞牛 [metaLineA] 同结构同顺序——年份 / 题材 / 地区。
  /// 题材、地区已由适配层翻好（[MediaDetail.genreLabels]/[MediaDetail.regionLabels]）。
  static String metaLineAFromDetail(MediaDetail detail) {
    final date = detail.releaseDate.trim();
    final year = date.length >= 4 ? date.substring(0, 4) : '';
    final values = <String>[
      if (year.isNotEmpty) year,
      ...detail.genreLabels.map((e) => e.trim()).where((e) => e.isNotEmpty),
      ...detail.regionLabels.map((e) => e.trim()).where((e) => e.isNotEmpty),
    ];
    return values.join(' / ');
  }

  /// 中立后端（Emby 等）的 metaLineB：时长 + 评分。时长优先单集分钟数，缺则按选中版本秒数
  /// 格式化。评分为 Emby 自有展示（飞牛此区不展示评分，故仅中立路径拼入；空则省略）。飞牛此处
  /// 第二段为「库/合集名」(ancestorName)，Emby 无对应字段、且剧名已在剧集面包屑展示，不重复拼入。
  static String metaLineBFromDetail(
    MediaDetail detail, {
    required int effectiveDurationSeconds,
    required AppLocalizations l10n,
  }) {
    final runtime = detail.runtimeMinutes > 0
        ? l10n.detailDurationMinutes(detail.runtimeMinutes)
        : formatDuration(effectiveDurationSeconds, l10n);
    final rating = detail.rating.trim();
    return <String>[
      if (runtime.isNotEmpty) runtime,
      if (rating.isNotEmpty) '⭐ $rating',
    ].join(' / ');
  }
}
