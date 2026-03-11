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

  static String runtimeText(PlayItem item) {
    if (item.runtime > 0) return '${item.runtime}分钟';
    return formatDuration(item.duration);
  }

  static String formatDuration(int durationSeconds) {
    if (durationSeconds <= 0) return '';
    final hour = durationSeconds ~/ 3600;
    final minute = (durationSeconds % 3600) ~/ 60;
    final second = durationSeconds % 60;

    if (hour > 0) return '$hour小时$minute分钟';
    if (minute > 0) return second > 0 ? '$minute分钟$second秒' : '$minute分钟';
    return '$second秒';
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

  static String remainText(int duration, int ts) {
    if (duration <= 0) return '';
    final remainSeconds = (duration - ts).clamp(0, duration);
    final hour = remainSeconds ~/ 3600;
    final minute = remainSeconds ~/ 60;
    final second = remainSeconds % 60;
    if (hour > 0) {
      final minuteInHour = (remainSeconds % 3600) ~/ 60;
      return '剩余 $hour 小时 $minuteInHour 分钟 $second 秒';
    }
    return '剩余 $minute 分钟 $second 秒';
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

  static String metaLineB(PlayItem item) {
    final values = [
      runtimeText(item),
      item.ancestorName,
    ].where((e) => e.isNotEmpty);
    return values.join(' / ');
  }
}

