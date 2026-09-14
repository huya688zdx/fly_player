import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/screens/screenshot_settings_screen.dart';
import 'package:fly_player/services/storage_access_service.dart';
import 'package:fly_player/widgets/common/local_file_browser_sheet.dart';

class _SystemFilePicker extends FilePicker {
  FilePickerResult? result;
  FileType? type;
  List<String>? extensions;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    this.type = type;
    extensions = allowedExtensions;
    return result;
  }
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fly_player/storage');
  late _SystemFilePicker picker;
  late List<String> androidCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    androidCalls = [];
    picker = _SystemFilePicker();
    FilePicker.platform = picker;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      androidCalls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    testWidgets(
      '$platform picks a usable local path with the system file picker',
      (tester) async {
        picker.result = FilePickerResult([
          PlatformFile(
            name: 'movie.mkv',
            path: '/Documents/movie.mkv',
            size: 123,
          ),
        ]);
        LocalBrowserFileSelection? selected;
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () {
                    unawaited(
                      LocalFileBrowserSheet.pickFile(
                        context,
                        title: 'Choose media',
                        allowedExtensions: ['mkv', 'mp4'],
                      ).then((value) => selected = value),
                    );
                  },
                  child: const Text('Pick'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('Pick'));
        await tester.pumpAndSettle();

        expect(selected?.identifier, '/Documents/movie.mkv');
        expect(selected?.displayName, 'movie.mkv');
        expect(picker.type, FileType.custom);
        expect(picker.extensions, ['mkv', 'mp4']);
        expect(androidCalls, isEmpty);
      },
      variant: TargetPlatformVariant({platform}),
    );

    testWidgets(
      '$platform Other settings hide Android screenshot save settings',
      (tester) async {
        await tester.pumpWidget(_app(const OtherSettingsScreen()));
        await tester.pumpAndSettle();

        final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));
        expect(find.text(l10n.settingsBookmarkManagerTitle), findsOneWidget);
        expect(find.text(l10n.settingsDanmakuTitle), findsOneWidget);
        expect(find.text(l10n.settingsScreenshotTitle), findsNothing);
        expect(androidCalls, isEmpty);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }
}
