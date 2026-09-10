import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/l10n/generated/app_localizations_zh.dart';
import 'package:fly_player/playback/settings/mpv_settings_store.dart';
import 'package:fly_player/providers/app_theme_provider.dart';
import 'package:fly_player/screens/mpv_player_settings_screen.dart';
import 'package:fly_player/theme/app_theme.dart';
import 'package:fly_player/widgets/common/app_ambient_page.dart';

void main() {
  testWidgets('桌面共用背景下 MPV 卡片透底且选中态与文字操作同色', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final colors = AppThemePalette.colorsFor(
      AppThemePreset.forest,
      accentTone: AppAccentTone.green,
      selectionTone: AppAccentTone.cyan,
    );
    final l10n = AppLocalizationsZh();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.buildFromColors(colors),
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AppAmbientPage(
          shareBackground: true,
          child: MpvPlayerSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final normalCard = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text(l10n.mpvPicturePresetAnimeLabel),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(
      (normalCard.decoration! as BoxDecoration).color,
      colors.surface.withValues(alpha: 0.16),
    );
    expect(
      tester
          .widget<Text>(find.text(l10n.mpvPicturePresetOffLabel).first)
          .style!
          .color,
      colors.selectionStrong,
    );
    final buttonContext = tester.element(find.text(l10n.commonRestoreDefault));
    expect(
      Theme.of(
        buttonContext,
      ).textButtonTheme.style!.foregroundColor!.resolve({}),
      colors.selectionStrong,
    );
  });

  testWidgets('保存音频自定义预设时建议名称使用本地化内置预设名', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      '${MpvSettingsCatalog.prefPrefix}${MpvSettingsCatalog.volumeGainKey}':
          '125',
      '${MpvSettingsCatalog.prefPrefix}${MpvSettingsCatalog.audioEqKey}':
          'soft',
      '${MpvSettingsCatalog.prefPrefix}${MpvSettingsCatalog.audioLimiterKey}':
          'light',
      '${MpvSettingsCatalog.prefPrefix}${MpvSettingsCatalog.audioBassBoostKey}':
          'low',
      '${MpvSettingsCatalog.prefPrefix}${MpvSettingsCatalog.audioVoiceEnhanceKey}':
          'low',
      '${MpvSettingsCatalog.prefPrefix}${MpvSettingsCatalog.channelMixKey}':
          'stereo',
    });

    final l10n = AppLocalizationsZh();
    final expectedBaseName = l10n.mpvAudioPresetBalancedLabel;

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppThemeProvider(),
        child: const MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MpvPlayerSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 主页快速预设与深入调节占满首屏，管理入口需滚动到可见（懒加载）。
    await tester.scrollUntilVisible(
      find.text(l10n.mpvCustomManagementTitle),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.mpvCustomManagementTitle));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.mpvAudioCustomTitle));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.mpvSaveCurrentAudioTitle));
    await tester.pumpAndSettle();

    final editableText = tester
        .widgetList<EditableText>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(EditableText),
          ),
        )
        .singleWhere((widget) => widget.controller.text.isNotEmpty);
    expect(editableText.controller.text, startsWith(expectedBaseName));
    expect(editableText.controller.text, isNot(startsWith('Balanced Boost')));
  });
}
