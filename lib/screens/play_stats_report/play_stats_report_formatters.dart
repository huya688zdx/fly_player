import '../../services/play_stats/play_stats.dart';
import '../../utils/play_detail_formatters.dart';

class PlayStatsReportFormatters {
  final Map<int, String> genreMap;
  final Map<String, String> countryMap;

  const PlayStatsReportFormatters({
    required this.genreMap,
    required this.countryMap,
  });

  String duration(int ms, {bool compact = false}) {
    final safeMs = ms < 0 ? 0 : ms;
    final value = Duration(milliseconds: safeMs);
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    if (compact) {
      if (hours > 0) {
        return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
      }
      final seconds = value.inSeconds.remainder(60);
      if (value.inMinutes > 0) {
        return seconds > 0
            ? '${value.inMinutes}m ${seconds}s'
            : '${value.inMinutes}m';
      }
      return '${value.inSeconds}s';
    }
    if (hours > 0) {
      return minutes > 0 ? '$hours 小时 $minutes 分钟' : '$hours 小时';
    }
    if (value.inMinutes > 0) {
      final seconds = value.inSeconds.remainder(60);
      return seconds > 0
          ? '${value.inMinutes} 分钟 $seconds 秒'
          : '${value.inMinutes} 分钟';
    }
    return '${value.inSeconds} 秒';
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

  String weekday(int weekday) => const <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
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
    return raw.trim().toLowerCase() == 'movie' ? '电影' : '剧集';
  }

  String startSourceLabel(PlayStartSource source) {
    return switch (source) {
      PlayStartSource.manual => '手动播放',
      PlayStartSource.manualSwitch => '手动切换',
      PlayStartSource.autoNext => '自动连播',
      PlayStartSource.replay => '重新播放',
      PlayStartSource.systemResume => '系统恢复',
    };
  }

  String historySubtitle(PlayHistoryRecord item) {
    return '${dateTime(item.startedAtMs)} · 观看 ${duration(item.watchedMs, compact: true)}';
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
    return '${startSourceLabel(item.startSource)} · 观看 ${duration(item.watchedMs, compact: true)} · ${dateTime(item.startedAtMs)}';
  }

  String topVideoSubtitle(PlayStatsTopVideo item) {
    final title = item.title.trim();
    final animeTitle = item.animeTitle.trim();
    final seasonTitle = item.seasonTitle.trim();
    final isMovie = item.videoKind.trim().toLowerCase() == 'movie';
    if (isMovie) {
      return '电影 · 观看 ${duration(item.playedMs, compact: true)}';
    }
    final parts = <String>[
      if (seasonTitle.isNotEmpty && !_containsNormalized(title, seasonTitle))
        seasonTitle,
      if (animeTitle.isNotEmpty &&
          !_containsNormalized(title, animeTitle) &&
          !_sameNormalized(animeTitle, seasonTitle))
        animeTitle,
      '观看 ${duration(item.playedMs, compact: true)}',
    ];
    return parts.join(' · ');
  }

  String affinitySubtitle(PlayStatsAffinityPerson item) {
    final occupation = _occupationLabel(item.role, item.job);
    final lead = occupation.isEmpty ? '常看人物' : occupation;
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
      '进度 ${percent(item.progress, fractionDigits: 0)}',
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

    const roleMap = <String, String>{
      'director': '导演',
      'producer': '制片',
      'executiveproducer': '监制',
      'writer': '编剧',
      'screenplay': '编剧',
      'story': '原作',
      'originalmusiccomposer': '作曲',
      'composer': '作曲',
      'music': '音乐',
      'editor': '剪辑',
      'cinematography': '摄影',
      'voice': '配音',
      'voiceactor': '配音',
      'actor': '演员',
      'actress': '演员',
    };

    const jobMap = <String, String>{
      'cast': '演员',
      'acting': '演员',
      'actor': '演员',
      'actress': '演员',
      'voice': '配音',
      'crew': '幕后',
      'directing': '导演',
      'director': '导演',
      'writing': '编剧',
      'writer': '编剧',
      'production': '制片',
      'editing': '剪辑',
      'sound': '音效',
      'camera': '摄影',
      'art': '美术',
      'visualeffects': '特效',
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
