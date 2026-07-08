import '../../services/play_stats/play_stats.dart';
import '../../utils/play_detail_formatters.dart';
import '../../l10n/generated/app_localizations.dart';

class PlayStatsReportFormatters {
  final AppLocalizations l10n;
  final Map<int, String> genreMap;
  final Map<String, String> countryMap;

  const PlayStatsReportFormatters({
    required this.l10n,
    required this.genreMap,
    required this.countryMap,
  });

  String duration(int ms, {bool compact = false}) {
    final safeMs = ms < 0 ? 0 : ms;
    final value = Duration(milliseconds: safeMs);
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    if (hours > 0) {
      return minutes > 0
          ? l10n.playStatsReportDurationHoursMinutes(hours, minutes)
          : l10n.playStatsReportDurationHours(hours);
    }
    if (value.inMinutes > 0) {
      final seconds = value.inSeconds.remainder(60);
      return seconds > 0
          ? l10n.playStatsDurationMinutes(value.inMinutes, seconds)
          : l10n.playStatsReportDurationMinutes(value.inMinutes);
    }
    return l10n.playStatsDurationSeconds(value.inSeconds);
  }

  String percent(double value, {int fractionDigits = 0}) {
    return '${(value * 100).toStringAsFixed(fractionDigits)}%';
  }

  String date(DateTime value, {bool compact = false}) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    if (compact) {
      return '$month/$day';
    }
    return '${value.year}-$month-$day';
  }

  String dateTime(int ms) {
    if (ms <= 0) {
      return '-';
    }
    final value = DateTime.fromMillisecondsSinceEpoch(ms);
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }

  String weekday(int weekday) => <String>[
    l10n.playStatsReportWeekdayMon,
    l10n.playStatsReportWeekdayTue,
    l10n.playStatsReportWeekdayWed,
    l10n.playStatsReportWeekdayThu,
    l10n.playStatsReportWeekdayFri,
    l10n.playStatsReportWeekdaySat,
    l10n.playStatsReportWeekdaySun,
  ][weekday.clamp(1, 7) - 1];

  String hourLabel(int hour) => hour.toString().padLeft(2, '0');

  String distributionLabel(
    PlayStatsDistributionBucket bucket,
    ContentMetric metric,
  ) {
    return switch (metric) {
      ContentMetric.genre =>
        genreMap[int.tryParse(bucket.id) ?? -1] ?? bucket.label,
      ContentMetric.country =>
        countryMap[bucket.id.toUpperCase()] ?? bucket.label,
      ContentMetric.year => bucket.label,
    };
  }

  String mediaLabel(String raw) {
    return raw.trim().toLowerCase() == 'movie'
        ? l10n.playStatsMovieList
        : l10n.playStatsEpisodeList;
  }

  String startSourceLabel(PlayStartSource source) {
    return switch (source) {
      PlayStartSource.manual => l10n.playStatsReportStartSourceManual,
      PlayStartSource.manualSwitch =>
        l10n.playStatsReportStartSourceManualSwitch,
      PlayStartSource.autoNext => l10n.playStatsStartSourceAutoNext,
      PlayStartSource.replay => l10n.playStatsReportStartSourceReplay,
      PlayStartSource.systemResume => l10n.playStatsStartSourceSystemResume,
    };
  }

  String historySubtitle(PlayHistoryRecord item) {
    return l10n.playStatsReportHistorySubtitle(
      dateTime(item.startedAtMs),
      duration(item.watchedMs, compact: true),
    );
  }

  String historyContext(PlayHistoryRecord item) {
    final animeTitle = item.animeTitle.trim();
    final seasonTitle = item.seasonTitle.trim();
    final isMovie = item.videoKind.trim().toLowerCase() == 'movie';
    final parts = <String>[
      mediaLabel(item.videoKind),
      if (!isMovie && animeTitle.isNotEmpty) animeTitle,
      if (!isMovie &&
          seasonTitle.isNotEmpty &&
          !_sameNormalized(seasonTitle, animeTitle))
        seasonTitle,
    ];
    return parts.join(' · ');
  }

  String historyMeta(PlayHistoryRecord item) {
    return l10n.playStatsReportHistoryMeta(
      startSourceLabel(item.startSource),
      duration(item.watchedMs, compact: true),
      dateTime(item.startedAtMs),
    );
  }

  String topVideoSubtitle(PlayStatsTopVideo item) {
    final title = item.title.trim();
    final animeTitle = item.animeTitle.trim();
    final seasonTitle = item.seasonTitle.trim();
    final isMovie = item.videoKind.trim().toLowerCase() == 'movie';
    if (isMovie) {
      return l10n.playStatsReportMovieWatchedSubtitle(
        duration(item.playedMs, compact: true),
      );
    }
    final parts = <String>[
      if (seasonTitle.isNotEmpty && !_containsNormalized(title, seasonTitle))
        seasonTitle,
      if (animeTitle.isNotEmpty &&
          !_containsNormalized(title, animeTitle) &&
          !_sameNormalized(animeTitle, seasonTitle))
        animeTitle,
      l10n.playStatsReportWatchedDuration(
        duration(item.playedMs, compact: true),
      ),
    ];
    return parts.join(' · ');
  }

  String affinitySubtitle(PlayStatsAffinityPerson item) {
    final occupation = _occupationLabel(item.role, item.job);
    final lead = occupation.isEmpty
        ? l10n.playStatsReportFrequentPerson
        : occupation;
    return '$lead · ${duration(item.watchedMs, compact: true)}';
  }

  String continueWatchingSubtitle(PlayStatsContinueWatchingItem item) {
    final title = item.title.trim();
    final animeTitle = item.animeTitle.trim();
    final seasonTitle = item.seasonTitle.trim();
    final parts = <String>[
      if (seasonTitle.isNotEmpty && !_containsNormalized(title, seasonTitle))
        seasonTitle,
      if (animeTitle.isNotEmpty &&
          !_containsNormalized(title, animeTitle) &&
          !_sameNormalized(seasonTitle, animeTitle))
        animeTitle,
      l10n.playStatsReportProgress(percent(item.progress, fractionDigits: 0)),
    ];
    return parts.join(' · ');
  }

  List<String> genreNames(Iterable<int> ids, {int maxCount = 3}) {
    return PlayDetailFormatters.genreNamesFromIds(
      ids,
      genreMap: genreMap,
      maxCount: maxCount,
    );
  }

  List<String> countryNames(Iterable<String> codes) {
    return PlayDetailFormatters.countryNamesFromCodes(
      codes,
      locateMap: countryMap,
    );
  }

  bool _containsNormalized(String source, String target) {
    final left = _normalizedText(source);
    final right = _normalizedText(target);
    if (left.isEmpty || right.isEmpty) {
      return false;
    }
    return left.contains(right);
  }

  bool _sameNormalized(String left, String right) {
    final leftValue = _normalizedText(left);
    final rightValue = _normalizedText(right);
    if (leftValue.isEmpty || rightValue.isEmpty) {
      return false;
    }
    return leftValue == rightValue;
  }

  String _normalizedText(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  String _occupationLabel(String role, String job) {
    final normalizedRole = _normalizedText(role);
    final normalizedJob = _normalizedText(job);

    final roleMap = <String, String>{
      'director': l10n.playStatsReportOccupationDirector,
      'producer': l10n.playStatsReportOccupationProducer,
      'executiveproducer': l10n.playStatsReportOccupationExecutiveProducer,
      'writer': l10n.playStatsReportOccupationWriter,
      'screenplay': l10n.playStatsReportOccupationWriter,
      'story': l10n.playStatsReportOccupationOriginal,
      'originalmusiccomposer': l10n.playStatsReportOccupationComposer,
      'composer': l10n.playStatsReportOccupationComposer,
      'music': l10n.playStatsReportOccupationMusic,
      'editor': l10n.playStatsReportOccupationEditor,
      'cinematography': l10n.playStatsReportOccupationCinematography,
      'voice': l10n.playStatsReportOccupationVoice,
      'voiceactor': l10n.playStatsReportOccupationVoice,
      'actor': l10n.playStatsReportOccupationActor,
      'actress': l10n.playStatsReportOccupationActor,
    };

    final jobMap = <String, String>{
      'cast': l10n.playStatsReportOccupationActor,
      'acting': l10n.playStatsReportOccupationActor,
      'actor': l10n.playStatsReportOccupationActor,
      'actress': l10n.playStatsReportOccupationActor,
      'voice': l10n.playStatsReportOccupationVoice,
      'crew': l10n.playStatsReportOccupationCrew,
      'directing': l10n.playStatsReportOccupationDirector,
      'director': l10n.playStatsReportOccupationDirector,
      'writing': l10n.playStatsReportOccupationWriter,
      'writer': l10n.playStatsReportOccupationWriter,
      'production': l10n.playStatsReportOccupationProducer,
      'editing': l10n.playStatsReportOccupationEditor,
      'sound': l10n.playStatsReportOccupationSound,
      'camera': l10n.playStatsReportOccupationCinematography,
      'art': l10n.playStatsReportOccupationArt,
      'visualeffects': l10n.playStatsReportOccupationVisualEffects,
    };

    final roleLabel = roleMap[normalizedRole];
    if (roleLabel != null && roleLabel.isNotEmpty) {
      return roleLabel;
    }

    final jobLabel = jobMap[normalizedJob];
    if (jobLabel != null && jobLabel.isNotEmpty) {
      return jobLabel;
    }

    if (job.trim().isNotEmpty) {
      return job.trim();
    }
    if (role.trim().isNotEmpty) {
      return role.trim();
    }
    return '';
  }
}

enum ContentMetric { genre, country, year }
