import '../../services/play_stats/play_stats.dart';
import '../../utils/play_detail_formatters.dart';
import '../../l10n/generated/app_localizations.dart';

class PlayStatsDebugFormatters {
  final AppLocalizations l10n;
  final Map<int, String> genreMap;
  final Map<String, String> countryMap;

  const PlayStatsDebugFormatters({
    required this.l10n,
    required this.genreMap,
    required this.countryMap,
  });

  String yesNo(bool value) => value ? l10n.playStatsYes : l10n.playStatsNo;

  String empty(String value) => value.trim().isEmpty ? '-' : value.trim();

  String zeroAsDash(int value) => value <= 0 ? '-' : '$value';

  String percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

  String duration(int ms) {
    final safeMs = ms < 0 ? 0 : ms;
    final duration = Duration(milliseconds: safeMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return l10n.playStatsDurationHours(hours, minutes, seconds);
    }
    if (minutes > 0) {
      return l10n.playStatsDurationMinutes(minutes, seconds);
    }
    return l10n.playStatsDurationSeconds(seconds);
  }

  String dateTime(int ms) {
    if (ms <= 0) {
      return '-';
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day $hour:$minute:$second';
  }

  String joinStrings(Iterable<String> values) {
    final joined = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' / ');
    return joined.isEmpty ? '-' : joined;
  }

  String joinInts(Iterable<int> values) {
    final joined = values.map((value) => '$value').join(', ');
    return joined.isEmpty ? '-' : joined;
  }

  String genreNames(Iterable<int> ids) {
    return joinStrings(
      PlayDetailFormatters.genreNamesFromIds(
        ids,
        genreMap: genreMap,
        maxCount: 12,
      ),
    );
  }

  String countryNames(Iterable<String> codes) {
    return joinStrings(
      PlayDetailFormatters.countryNamesFromCodes(codes, locateMap: countryMap),
    );
  }

  String startSource(PlayStartSource source) {
    return switch (source) {
      PlayStartSource.manual => l10n.playStatsStartSourceManual,
      PlayStartSource.manualSwitch => l10n.playStatsStartSourceManualSwitch,
      PlayStartSource.autoNext => l10n.playStatsStartSourceAutoNext,
      PlayStartSource.replay => l10n.playStatsStartSourceReplay,
      PlayStartSource.systemResume => l10n.playStatsStartSourceSystemResume,
    };
  }
}

class PlayStatsDebugRowData {
  final String label;
  final String value;

  const PlayStatsDebugRowData(this.label, this.value);
}
