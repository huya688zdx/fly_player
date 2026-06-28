import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/utils/play_detail_formatters.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));

  group('PlayDetailFormatters.formatDuration', () {
    test('按原有中文格式展示时长', () {
      expect(PlayDetailFormatters.formatDuration(3661, l10n), '1小时1分钟');
      expect(PlayDetailFormatters.formatDuration(125, l10n), '2分钟5秒');
      expect(PlayDetailFormatters.formatDuration(120, l10n), '2分钟');
      expect(PlayDetailFormatters.formatDuration(9, l10n), '9秒');
    });
  });

  group('PlayDetailFormatters.remainText', () {
    test('按原有中文格式展示剩余时长', () {
      expect(
        PlayDetailFormatters.remainText(3661, 0, l10n),
        '剩余 1 小时 1 分钟 1 秒',
      );
      expect(PlayDetailFormatters.remainText(125, 60, l10n), '剩余 1 分钟 5 秒');
    });
  });
}
