import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/services/app_log_service.dart';
import 'package:fly_player/utils/swallowed_error_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await AppLogService.instance.clear();
  });

  test('记录被降级吞掉的异常并保留上下文', () async {
    final stackTrace = StackTrace.current;

    await logSwallowedError(
      action: '加载附加信息',
      id: 'item-1',
      error: StateError('boom'),
      stackTrace: stackTrace,
      source: 'test',
    );

    final entry = AppLogService.instance.latestEntry;
    expect(entry, isNotNull);
    expect(entry!.level, AppLogLevel.warning);
    expect(entry.source, 'test');
    expect(entry.message, contains('boom'));
    expect(entry.details, contains('action=加载附加信息'));
    expect(entry.details, contains('id=item-1'));
    expect(entry.stackTraceText, stackTrace.toString());
  });
}
