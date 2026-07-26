import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fly_player/l10n/generated/app_localizations.dart';
import 'package:fly_player/media_backend/detail/media_detail.dart';
import 'package:fly_player/ui/credit_person_presenter.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('zh', 'CN'));

  MediaDetailPerson person({
    String name = 'x',
    String role = '',
    String department = '',
  }) {
    return MediaDetailPerson(
      id: 'p',
      name: name,
      role: role,
      department: department,
    );
  }

  group('CreditPersonPresenter.displayName', () {
    test('名字非空：去首尾空白', () {
      expect(
        CreditPersonPresenter.displayName(person(name: '  演员甲 '), l10n),
        '演员甲',
      );
    });

    test('名字空 / 全空白：回退「未知」', () {
      expect(CreditPersonPresenter.displayName(person(name: ''), l10n), '未知');
      expect(
        CreditPersonPresenter.displayName(person(name: '   '), l10n),
        '未知',
      );
    });
  });

  group('CreditPersonPresenter.displaySubTitle', () {
    test('角色优先：饰 + 角色名', () {
      expect(
        CreditPersonPresenter.displaySubTitle(person(role: '主角'), l10n),
        '饰 主角',
      );
    });

    test('角色为 (voice) 跳过 → 落到职务', () {
      expect(
        CreditPersonPresenter.displaySubTitle(
          person(role: '(voice)', department: 'Director'),
          l10n,
        ),
        '导演',
      );
    });

    test('职务映射中文（大小写不敏感）', () {
      expect(
        CreditPersonPresenter.displaySubTitle(
          person(department: 'director'),
          l10n,
        ),
        '导演',
      );
      expect(
        CreditPersonPresenter.displaySubTitle(
          person(department: 'Actor'),
          l10n,
        ),
        '演员',
      );
      expect(
        CreditPersonPresenter.displaySubTitle(
          person(department: 'Screenplay'),
          l10n,
        ),
        '编剧',
      );
    });

    test('未知职务原样返回', () {
      expect(
        CreditPersonPresenter.displaySubTitle(
          person(department: 'Producer'),
          l10n,
        ),
        'Producer',
      );
    });

    test('角色与职务皆空 → 空串', () {
      expect(CreditPersonPresenter.displaySubTitle(person(), l10n), '');
    });
  });
}
