import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/utils/app_error_reporter.dart';
import 'package:fly_player/utils/app_exception.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));

  AppException errorWithMessage(String message) {
    return AppException(
      kind: AppExceptionKind.transient,
      action: '测试操作',
      message: message,
    );
  }

  group('AppErrorReporter.messageFor', () {
    test('错误消息为空时使用本地化的默认失败文案', () {
      expect(
        AppErrorReporter.messageFor(errorWithMessage('   '), l10n: l10n),
        '操作失败',
      );
    });

    test('带前缀时保持原有展示格式', () {
      expect(
        AppErrorReporter.messageFor(
          errorWithMessage('   '),
          prefix: '刷新详情',
          l10n: l10n,
        ),
        '刷新详情: 操作失败',
      );
    });
  });
}
