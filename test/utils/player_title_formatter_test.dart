import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/utils/player_title_formatter.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));

  test('formatPlayerTitle 保持原有季集标题格式', () {
    expect(
      formatPlayerTitle(
        seriesTitle: '剧名',
        episodeTitle: '标题',
        seasonNumber: 2,
        episodeNumber: 3,
        fallbackTitle: '',
        l10n: l10n,
      ),
      '剧名 第2季 第3集 标题',
    );
  });
}
