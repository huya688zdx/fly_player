import '../l10n/generated/app_localizations.dart';
import '../models/download_record_tokens.dart';
import 'play_detail_formatters.dart';

const String _legacyInterruptedMessage = '\u4e0b\u8f7d\u5df2\u4e2d\u65ad';
const String _legacyResourceUnavailableMessage =
    '\u65e0\u6cd5\u83b7\u53d6\u4e0b\u8f7d\u8d44\u6e90';
const String _legacyLocalResolution = '\u672c\u5730';
const String _legacyCacheResolution = '\u7f13\u5b58';

String localizeDownloadRecordText(String value, AppLocalizations l10n) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed == downloadInterruptedMessageToken ||
      trimmed == _legacyInterruptedMessage) {
    return l10n.downloadInterruptedError;
  }
  if (trimmed == downloadResourceUnavailableMessageToken ||
      trimmed == _legacyResourceUnavailableMessage) {
    return l10n.downloadResourceUnavailable;
  }
  return localizeDownloadResolution(
    localizeDownloadDurationText(trimmed, l10n),
    l10n,
  );
}

String localizeDownloadResolution(String value, AppLocalizations l10n) {
  final trimmed = value.trim();
  if (trimmed == downloadLocalResolutionToken ||
      trimmed == _legacyLocalResolution) {
    return l10n.downloadLocalResolution;
  }
  if (trimmed == downloadCacheResolutionToken ||
      trimmed == _legacyCacheResolution) {
    return l10n.storageCacheResolutionFallback;
  }
  return value;
}

String localizeDownloadDurationText(String value, AppLocalizations l10n) {
  final trimmed = value.trim();
  if (!trimmed.startsWith(downloadRecoveredDurationTokenPrefix)) return value;
  final rawSeconds = trimmed.substring(
    downloadRecoveredDurationTokenPrefix.length,
  );
  final seconds = int.tryParse(rawSeconds);
  if (seconds == null) return value;
  return PlayDetailFormatters.formatDuration(seconds, l10n);
}

String localizeDownloadTitleTokens(String value, AppLocalizations l10n) {
  return value.replaceAllMapped(
    RegExp('${RegExp.escape(downloadSeasonLabelTokenPrefix)}(\\d+)'),
    (match) {
      final season = int.tryParse(match.group(1) ?? '');
      return season == null
          ? match.group(0) ?? ''
          : l10n.playerEpisodeSeasonTemplate(season);
    },
  );
}
