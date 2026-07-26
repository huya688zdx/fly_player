import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/l10n/generated/app_localizations_zh.dart';
import 'package:fly_player/ui/audio_track_label_localizer.dart';

void main() {
  final AppLocalizations l10n = AppLocalizationsZh();

  test('已知语言 code 拼出「语言音频」文案', () {
    expect(audioTrackLabel(l10n, 'eng'), '英语音频');
    expect(audioTrackLabel(l10n, 'jpn'), '日语音频');
  });

  test('未知 / 空语言返回空串，不臆造文案', () {
    expect(audioTrackLabel(l10n, 'unknown'), '');
    expect(audioTrackLabel(l10n, ''), '');
  });
}
