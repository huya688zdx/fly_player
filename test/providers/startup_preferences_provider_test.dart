import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/providers/startup_preferences_provider.dart';

void main() {
  test('默认关闭并在加载后采用已保存的启动目的地偏好', () async {
    final provider = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => true,
    );

    expect(provider.isReady, isFalse);
    expect(provider.openPosterHomeOnStartup, isFalse);

    await provider.load();

    expect(provider.isReady, isTrue);
    expect(provider.openPosterHomeOnStartup, isTrue);
  });

  test('保存成功后更新启动目的地偏好', () async {
    bool? saved;
    final provider = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => false,
      savePreference: (value) async {
        saved = value;
        return true;
      },
    );
    await provider.load();

    await provider.setOpenPosterHomeOnStartup(true);

    expect(provider.openPosterHomeOnStartup, isTrue);
    expect(saved, isTrue);
  });

  test('保存失败时恢复更新前的启动目的地偏好', () async {
    final provider = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => false,
      savePreference: (_) async => throw StateError('save failed'),
    );
    await provider.load();

    await expectLater(
      provider.setOpenPosterHomeOnStartup(true),
      throwsStateError,
    );

    expect(provider.openPosterHomeOnStartup, isFalse);
  });

  test('存储返回 false 时恢复更新前的启动目的地偏好', () async {
    final savedValues = <bool>[];
    final provider = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => false,
      savePreference: (value) async {
        savedValues.add(value);
        return value ? false : true;
      },
    );
    await provider.load();

    await expectLater(
      provider.setOpenPosterHomeOnStartup(true),
      throwsStateError,
    );

    expect(provider.openPosterHomeOnStartup, isFalse);
    expect(savedValues, <bool>[true, false]);
  });

  test('读取失败时安全回退为关闭并完成初始化', () async {
    final provider = StartupPreferencesProvider(
      autoLoad: false,
      loadPreference: () async => throw StateError('load failed'),
    );

    await provider.load();

    expect(provider.isReady, isTrue);
    expect(provider.openPosterHomeOnStartup, isFalse);
  });
}
